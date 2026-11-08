import { test } from "node:test";
import assert from "node:assert/strict";
import { buildGoogleRequest, computeRoutes, createRoutesHandler, FIELDS } from "../supabase/functions/commute-routes/provider.mjs";

const input = { origin: { latitude: 14.6, longitude: 121 },
  destination: { latitude: 14.6043, longitude: 120.9884 }, mode: "Transit" };
const now = new Date("2026-11-08T00:00:00Z");
test("driving uses traffic-aware routes; walking never uses a transit preference", () => {
  assert.equal(buildGoogleRequest({ ...input, mode: "Driving" }, now).routingPreference, "TRAFFIC_AWARE");
  const walking = buildGoogleRequest({ ...input, mode: "Walking" }, now);
  assert.equal(walking.travelMode, "WALK");
  assert.equal(walking.routingPreference, undefined);
});
test("transit modes and arrival time follow Google semantics", () => {
  const train = buildGoogleRequest({ ...input, mode: "Train", arriveBy: "2026-11-08T01:00:00Z" }, now);
  assert.equal(train.travelMode, "TRANSIT");
  assert.deepEqual(train.transitPreferences.allowedTravelModes, ["RAIL"]);
  assert.equal(train.departureTime, undefined);
  assert.equal(train.arrivalTime, "2026-11-08T01:00:00.000Z");
  assert.deepEqual(buildGoogleRequest({ ...input, mode: "Bus / UV" }, now).transitPreferences.allowedTravelModes, ["BUS"]);
});
test("invalid coordinates, dates and jeepney requests never reach Google", () => {
  assert.throws(() => buildGoogleRequest({ ...input, mode: "Jeepney" }, now));
  assert.throws(() => buildGoogleRequest({ ...input, origin: { latitude: 91, longitude: 0 } }, now));
  assert.throws(() => buildGoogleRequest({ ...input, arriveBy: "bad-date" }, now));
});
test("the server key stays in an upstream header with a scoped field mask", async () => {
  const result = await computeRoutes(buildGoogleRequest(input, now), "server-only-test-key", async (url, options) => {
    assert.equal(options.headers["X-Goog-Api-Key"], "server-only-test-key");
    assert.equal(options.headers["X-Goog-FieldMask"], FIELDS);
    assert.ok(!options.body.includes("server-only-test-key"));
    return new Response(JSON.stringify({ routes: [{ duration: "1800s" }] }), { status: 200 });
  });
  assert.equal(result.routes[0].duration, "1800s");
});
test("provider failures and empty routes do not fabricate estimates", async () => {
  await assert.rejects(computeRoutes({}, "test", async () => new Response("failure", { status: 503 })));
  const empty = await computeRoutes({}, "test", async () => new Response("{}"));
  assert.deepEqual(empty.routes, []);
});

const request = (headers = {}) => new Request("https://edge.example/commute-routes", {
  method: "POST", headers, body: JSON.stringify(input),
});
test("unauthenticated users and unapproved browser origins never call the paid provider", async () => {
  let calls = 0;
  const handler = createRoutesHandler({ authenticate: async () => null, consumeQuota: async () => true,
    key: "test", allowedOrigins: ["https://app.example"], compute: async () => { calls++; return {}; } });
  assert.equal((await handler(request())).status, 401);
  assert.equal((await handler(request({ Authorization: "Bearer invalid" }))).status, 401);
  assert.equal((await handler(request({ Origin: "https://other.example" }))).status, 403);
  assert.equal(calls, 0);
});
test("rate limiting and a failed quota store both fail closed", async () => {
  let calls = 0;
  const config = { authenticate: async () => ({}), key: "test", compute: async () => { calls++; return {}; } };
  const denied = await createRoutesHandler({ ...config, consumeQuota: async () => false })(request({ Authorization: "Bearer test" }));
  assert.equal(denied.status, 429);
  assert.equal(denied.headers.get("Retry-After"), "60");
  const unavailable = await createRoutesHandler({ ...config, consumeQuota: async () => { throw new Error("database down"); } })(request({ Authorization: "Bearer test" }));
  assert.equal(unavailable.status, 503);
  assert.equal(calls, 0);
});
test("an authenticated, permitted response is private and never contains its key", async () => {
  const handler = createRoutesHandler({ authenticate: async () => ({}), consumeQuota: async () => true,
    key: "server-only", allowedOrigins: ["https://app.example"], compute: async () => ({ routes: [] }) });
  const response = await handler(request({ Authorization: "Bearer test", Origin: "https://app.example" }));
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("Cache-Control"), "no-store, private");
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), "https://app.example");
  assert.ok(!(await response.text()).includes("server-only"));
});
