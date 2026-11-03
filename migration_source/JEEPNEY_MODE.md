# Tamaraw Time v8 — OSM-backed Jeepney Planner

## What changed

The **Jeepney** travel mode in Commute Planner now queries live OpenStreetMap (OSM) route-relation metadata through the public Overpass API, then requests the corresponding route geometry and mapped stops from the OSM Public Transport → GeoJSON API.

A candidate is only displayed when:
1. The OSM relation is explicitly identifiable as a jeepney / public utility jeepney service (e.g. `bus=share_taxi`, `network=LTFRB PUJ`, a clearly jeepney-labeled name, or a traditional `T###` route ref).
2. It has actual mapped route geometry with at least two points.
3. It has an **ordered pair of mapped stops**, the first within 900 m of the student's GPS location and the second within 900 m of the selected FEU campus.
4. The stop direction makes progress toward the campus (no reverse-order trips).

It draws the **source geometry** as an amber Leaflet route and marks the actual mapped boarding and alighting stops. Results link to the original OSM relation. There is no synthetic road geometry, stop, timetable, fare, or route transfer.

## Limitations you must show testers

- OSM is a volunteer-maintained mapping database, **not live proof that a jeepney service still operates, or that boarding is permitted today**. Validate routes/stops with signs and operators.
- Route searches are not exhaustive. Some jeepney services lack consistent `route` relations, correctly tagged vehicle types, geometry or ordered stops. Missing data means **no route shown**, even if a real-world service exists.
- Only **direct one-jeepney options** are considered. Multi-transfer itineraries are intentionally unsupported.
- Distances shown between your GPS position and mapped stops are **straight-line distances**, not walking directions.
- **No live jeepney ETA, fare, traffic, wait time, frequency or vehicle position** is available. The existing manual journey-time estimate continues to drive departure calculation for Jeepney mode.
- Public unauthenticated Overpass and route conversion services may throttle, fail, or block CORS. The app shows a fallback to https://sakay.ph/ with no invented transit information.
- The route search shares the current GPS coordinates with third-party routing APIs when the user presses Find route. Tamaraw Time does not store GPS history in the Supabase database.
- OSM public tile service is intended for modest usage and subject to the OSMF tile usage policy. For larger deployments, select appropriate commercial or self-hosted providers.

## Deploying on GitHub Pages

Unzip and upload the **contents** (not the containing folder) into your existing GitHub Pages publishing directory:

```
index.html
app.js
jeepney-routing.js          <-- NEW REQUIRED FILE
styles.css
cloud-store.js
cloud-config.js             <-- preserve your real project URL and publishable key
assets/
  tamaraw-logo.png
  favicon.ico
```

Optional: `demo.html`, `demo-cloud.js`, `README.md`, `ANIMATIONS.md` and this guide.

**Keep a backup of your existing cloud-config.js** before uploading. The ZIP contains placeholder credentials; replace them with your existing valid Supabase Project URL and publishable key. Do not upload a database password or service-role key. The `schema.sql` file is for new Supabase projects only.

## Try it

1. Open the deployed site over HTTPS and sign in (or open `demo.html` for the non-cloud demo).
2. Add a class and set the correct FEU campus.
3. Open **Commute Planner**, select **Jeepney**.
4. Tap **Start live GPS** and approve the browser's location permission.
5. Tap **Find route**. If a sufficiently complete OSM relation is available, tap a candidate to focus its real map shape and mapped stops. Otherwise, read the reason and use the Sakay.ph fallback.
6. Confirm that the departure recommendation still uses your **editable travel time** in Jeepney mode.

## Sources

- OSM Philippines transport tagging: https://wiki.openstreetmap.org/wiki/Philippines/Public_transportation
- OSM Jeepney and UV Express route catalog: https://wiki.openstreetmap.org/wiki/Metro_Manila/Jeepney_and_UV_Express_routes
- OSM Public Transport → GeoJSON API: https://openstreetmap.tools/public_transport_geojson/docs
- Sakay.ph: https://sakay.ph/

## Testing

Run `node test-jeepney.js` and `node test-logic.js` for mocked-service route direction, tag classification, mapped-stop constraints, and departure logic. These **do not certify production API availability**. A live end-to-end test must be run from the deployed HTTPS site in the supported region.
