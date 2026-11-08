# Sakay.ph GTFS provenance and legal considerations

Repository: https://github.com/sakayph/gtfs
License: https://github.com/sakayph/gtfs/blob/master/LICENSE.md

This repository contains a historical Metro Manila transit feed from the Philippine Transit App Challenge, adapted for Sakay.ph. Its license is NOT necessarily an unrestricted permissive software license. Read its DOTC Developer License Agreement and obtain permission / ensure license compliance before copying, redistributing, or publishing data.

**For that reason this kit DOES NOT redistribute Sakay.ph GTFS contents.** It contains a generic import tool that you can run locally on a GTFS directory you have permission to use. The resulting output is labeled `unverified_historical` and MUST NOT be shown as a current operating route unless verified independently.

Do not treat GTFS `stop_times` as real-time arrivals. Do not infer real-time traffic, live jeepney availability, current fare, or current bus stop operation from historical files.

Repo URL: https://github.com/sakayph/gtfs
Original web app URL: https://github.com/sakayph/sakayph
Fares repository URL: https://github.com/sakayph/fares (historical; DO NOT import old values as current fares)
