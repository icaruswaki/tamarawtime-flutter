param(
    [ValidateSet('Check','Build','Start','Stop','Smoke')][string]$Action = 'Check',
    [double]$OriginLatitude = 14.65,
    [double]$OriginLongitude = 121.03,
    [double]$DestinationLatitude = 14.6043,
    [double]$DestinationLongitude = 120.9884
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker CLI is missing. Install and start Docker Desktop with Linux containers, then rerun this command.'
}
$containerOS = docker info --format '{{.OSType}}'
if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop is not ready.' }
if ($containerOS.Trim() -ne 'linux') { throw 'OTP requires Docker Desktop Linux containers.' }
$composeFile = Join-Path $PSScriptRoot 'compose.yaml'
switch ($Action) {
    'Check' { docker compose -f $composeFile config --quiet }
    'Build' {
        docker compose -f $composeFile run --rm validator prepare --data /data
        if ($LASTEXITCODE -ne 0) { throw 'Current data validation failed; no graph was built.' }
        docker compose -f $composeFile run --rm otp-build
        if ($LASTEXITCODE -ne 0) { throw 'OTP graph build failed; no ready graph was sealed.' }
        docker compose -f $composeFile run --rm validator seal --data /data
    }
    'Start' {
        docker compose -f $composeFile run --rm validator check --data /data
        if ($LASTEXITCODE -ne 0) { throw 'A validated graph is required. Run Build first.' }
        docker compose -f $composeFile up -d otp gateway
    }
    'Stop' { docker compose -f $composeFile down }
    'Smoke' {
        $health = Invoke-RestMethod 'http://127.0.0.1:8090/health'
        if (-not $health.ready) { throw 'Gateway or OTP is not ready.' }
        $body = @{
            origin = @{latitude = $OriginLatitude; longitude = $OriginLongitude}
            destination = @{latitude = $DestinationLatitude; longitude = $DestinationLongitude}
            mode = 'Train'
        } | ConvertTo-Json -Depth 5
        $plan = Invoke-RestMethod 'http://127.0.0.1:8090/plan' -Method Post -ContentType 'application/json' -Body $body
        $edges = @($plan.data.planConnection.edges | Where-Object { $null -ne $_ })
        if ($plan.scheduleValidated -ne $true -or $edges.Count -eq 0) {
            throw 'No validated connected rail itinerary returned. Transit routing acceptance has NOT passed; check service dates, coverage, walking access and the requested journey/time.'
        }
        foreach ($edge in $edges) {
            $rideLegs = @($edge.node.legs | Where-Object { $_.transitLeg -eq $true })
            if ($rideLegs.Count -eq 0 -or $edge.node.duration -le 0 -or -not $edge.node.start -or -not $edge.node.end) {
                throw 'OTP returned an incomplete journey. Transit routing acceptance has NOT passed.'
            }
        }
        Write-Output "OTP returned $($edges.Count) validated connected rail itineraries. Inspect the steps below and verify the same journey in Flutter."
        $plan | ConvertTo-Json -Depth 30
    }
}
if ($LASTEXITCODE -ne 0) { throw "Docker command failed with exit code $LASTEXITCODE." }
