export const ROUTES_URL = "https://routes.googleapis.com/directions/v2:computeRoutes";
export const FIELDS = [
  "routes.duration", "routes.distanceMeters", "routes.polyline.encodedPolyline",
  "routes.legs.steps.travelMode", "routes.legs.steps.staticDuration",
  "routes.legs.steps.distanceMeters", "routes.legs.steps.polyline.encodedPolyline",
  "routes.legs.steps.navigationInstruction.instructions",
  "routes.legs.steps.transitDetails", "routes.travelAdvisory.transitFare",
].join(",");

export function buildGoogleRequest(input, now = new Date()) {
  const modes = { Walking: "WALK", Driving: "DRIVE", Transit: "TRANSIT", Train: "TRANSIT", "Bus / UV": "TRANSIT" };
  if (!input || typeof input !== "object" || !Object.hasOwn(modes, input.mode)) {
    throw new Error("unsupported_mode");
  }
  const waypoint = (point) => {
    if (!point || !Number.isFinite(point.latitude) || !Number.isFinite(point.longitude) ||
        Math.abs(point.latitude) > 90 || Math.abs(point.longitude) > 180) throw new Error("invalid_coordinates");
    return { location: { latLng: { latitude: point.latitude, longitude: point.longitude } } };
  };
  const travelMode = modes[input.mode];
  const body = { origin: waypoint(input.origin), destination: waypoint(input.destination),
    travelMode, computeAlternativeRoutes: true, languageCode: "en-US", units: "METRIC" };
  if (travelMode === "DRIVE") {
    body.routingPreference = "TRAFFIC_AWARE";
    body.departureTime = now.toISOString();
  }
  if (travelMode === "TRANSIT") {
    const requestedArrival = input.arriveBy ? new Date(input.arriveBy) : null;
    if (requestedArrival && (!Number.isFinite(+requestedArrival) || requestedArrival <= now ||
        requestedArrival - now > 8 * 86400000)) throw new Error("invalid_arrival_time");
    if (requestedArrival) body.arrivalTime = requestedArrival.toISOString();
    else body.departureTime = now.toISOString();
    if (input.mode === "Train") body.transitPreferences = { allowedTravelModes: ["RAIL"] };
    if (input.mode === "Bus / UV") body.transitPreferences = { allowedTravelModes: ["BUS"] };
  }
  return body;
}

export async function computeRoutes(body, key, request = fetch) {
  const response = await request(ROUTES_URL, {
    method: "POST", headers: { "Content-Type": "application/json",
      "X-Goog-Api-Key": key, "X-Goog-FieldMask": FIELDS },
    body: JSON.stringify(body), signal: AbortSignal.timeout(12000),
  });
  if (!response.ok) throw new Error("provider_unavailable");
  const data = await response.json();
  return { routes: Array.isArray(data.routes) ? data.routes : [], source: "Google Routes" };
}

export function createRoutesHandler({ authenticate, consumeQuota, key,
  allowedOrigins = [], compute = computeRoutes }) {
  return async (req) => {
    const origin = req.headers.get("origin");
    const headers = {
      "Content-Type": "application/json", "Cache-Control": "no-store, private", Vary: "Origin",
      "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    };
    if (origin && allowedOrigins.includes(origin)) headers["Access-Control-Allow-Origin"] = origin;
    const reply = (status, data) => new Response(JSON.stringify(data), { status, headers });
    if (origin && !allowedOrigins.includes(origin)) return reply(403, { error: "origin_not_allowed" });
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers });
    if (req.method !== "POST") return reply(405, { error: "method_not_allowed" });
    const authorization = req.headers.get("authorization") ?? "";
    if (!authorization.startsWith("Bearer ")) return reply(401, { error: "sign_in_required" });
    let context;
    try { context = await authenticate(authorization); } catch { context = null; }
    if (!context) return reply(401, { error: "sign_in_required" });
    let body;
    try {
      const text = await req.text();
      if (text.length > 4096) return reply(413, { error: "request_too_large" });
      body = buildGoogleRequest(JSON.parse(text));
    } catch { return reply(400, { error: "invalid_route_request" }); }
    if (!key) return reply(503, { message: "Live travel estimates are currently unavailable." });
    try {
      if (await consumeQuota(context) !== true) {
        headers["Retry-After"] = "60";
        return reply(429, { message: "Route refresh limit reached. Please try again later." });
      }
      return reply(200, await compute(body, key));
    } catch {
      return reply(503, { message: "Live travel estimates are currently unavailable." });
    }
  };
}
