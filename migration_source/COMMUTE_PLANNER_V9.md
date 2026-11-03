# Tamaraw Time v9 — evidence-backed journey steps

The route list uses already integrated OpenStreetMap mapped jeepney route relations, their ordered stops and route geometry. Selecting a direct jeepney candidate now adds a four-step commute plan, with optional pedestrian directions to/from stops via routing.openstreetmap.de. Blue dashed lines are pedestrian routes returned by the walking service; orange lines are mapped OSM jeepney routes.

## Critical limits

- Only direct routes with mapped route geometry and directional ordered stops can be suggested. We do **not** invent transfers, stop coordinates, route operation, fares, waiting times or departure schedules.
- If no direct route qualifies, the app links Sakay.ph. It does not silently use the old GTFS dataset.
- If walking routing fails, the app does **not** present straight-line distance as actual walking distance or make up an ETA.
- The manual total commute time remains in the departure calculation. The walking portion shown is only a partial route estimate and is not applied as the full journey ETA.
- External mapping services see GPS origin coordinates when route search is requested. Students must consent to browser location permission.
- This is a prototype, not production navigation or real-time transit service verification.

## GitHub Pages

Upload index.html, app.js, styles.css, jeepney-routing.js, cloud-store.js, cloud-config.js (preserve your own publishable key and URL), and the existing assets folder. Open the commute planner, enable GPS, select Jeepney and Find route.
