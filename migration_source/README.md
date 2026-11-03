# Tamaraw Time v8 — Live GPS + OSM-backed Jeepney Mode

**NEW:** The Jeepney mode now checks real OpenStreetMap route relations with mapped stops, only shows directionally plausible direct jeepney connections, and offers Sakay.ph when data is insufficient. See **JEEPNEY_MODE.md** for limitations and deployment.

# Previous v7 design improvements

## Changes based on student feedback

- **Animation**: New page transitions, staggered dashboard cards, visual tutorial transitions, route and GPS effects, animated guide demonstrations. Respects `prefers-reduced-motion`.
- **Color schemes**: FEU Forest, Coastal Blue, Golden Hour, and Midnight. Choose in **Settings → Color scheme → Save settings**. The selected theme is stored in the existing Supabase `app_states.payload.settings.theme` field (no database migration required).
- **Visual tutorial**: Five illustrated mini-screens in a walkthrough, rather than paragraphs of instructions. Replay in Settings.
- **AM/PM controls**: Explicit, strongly highlighted 12-hour AM/PM switches for *class start and end* in the Add Class dialog. Converts to 24-hour `HH:MM` for the existing data format. All class time and date calculations still work with previously saved schedules.
- **Automatic departure**: After a class exists, leave/get-ready times are calculated from class start, travel time, preparation time and buffer. For Walking or Driving, with permission and internet access, GPS triggers route lookup automatically (no need to press Apply Estimate), then updates the commute planner. Route times are routing estimates, **not live traffic**. If GPS or routing is unavailable, an editable fallback is used.
- **Previous v6 features retained**: Interactive Leaflet map, live GPS marker, school campus pins, walking/driving routes, transit-mode selector, cloud schedule and private researcher activity logs.
- **Old bugs fixed**: The `classForm` definition missing from v6 is restored, allowing Add Class to work.

## Quick UI preview (does not need Supabase)

Open `demo.html` via a local web server (e.g., `python -m http.server 8000`, browse to `http://localhost:8000/demo.html`) or on GitHub Pages. It uses simulated account and schedule data **in memory only**. It is not a separate database and **does not save changes**. `index.html` remains the actual cloud version.

## Deploy to GitHub Pages

1. Unzip the files and upload `index.html`, `app.js`, `styles.css`, `cloud-config.js`, `cloud-store.js`, `schema.sql`, etc. to your GitHub Pages publishing folder. For a public demo you can additionally upload `demo.html` and `demo-cloud.js`, but **do not point users to the demo for research data collection**.
2. In `cloud-config.js`, set the Supabase project URL and publishable/anon key. **Never use a secret/service-role key in frontend code**.
3. If this is a new database, run `schema.sql` in Supabase SQL Editor once. If v6 is already working, do **not** drop or recreate tables; v7 uses the same schema.
4. Enable Email sign-in and configure the GitHub Pages URL in Supabase Authentication redirect settings.
5. Open `index.html` over HTTPS, test signup/login, add a class at 9:00 PM then a second at 9:00 AM, change theme and save, reload, and confirm it persists.
6. On a smartphone, open **Commute Planner**, select Walking or Driving, start GPS, and allow location permission. Routes require a public third-party service and may not always respond. The map and GPS are not available offline.

## Privacy and limitations

- GPS requires the student's permission and only runs in the foreground. GPS coordinates are not stored in Supabase by this app; route coordinates are sent to third-party routing services if a route is requested.
- Public-transport routes for Jeepney / Train / Bus / UV are not available without a verified transit provider; they use the user's estimated journey minutes. No stops or live traffic times are invented.
- The public routing endpoint is best-effort, not suitable as a production SLA. It may rate-limit or fail; replace it with an appropriate routing service before a large rollout.
- On a non-Philippine-device timezone, next-class weekday calculation in this MVP uses the device timezone; the header clock always uses Asia/Manila. Test on Philippine devices for campus use.
- `schema.sql` logs only named study events (class added/deleted, commute/settings saved, GPS checked, map opened). Researcher reporting remains in Supabase.
- GitHub Pages can't host a server-side database; the main app continues to require Supabase cloud setup.

## Branding restored (v7.1)

- The original logo is now shown in the sign-in panel and sidebar.
- Upload **tamaraw-logo.png** and **favicon.ico** alongside index.html, styles.css, app.js, cloud-config.js and cloud-store.js.
- The logo/favicons use relative URLs, suitable for a GitHub Pages repository subpath.
- If the old tab icon persists, hard refresh (Ctrl+Shift+R) or open a private window.
- For Flutter, add the PNG under assets/images and list it in pubspec.yaml; Flutter launcher icons require separate platform icon generation.


## v9 journey planning
See `COMMUTE_PLANNER_V9.md` for direct mapped jeepney journeys plus walking directions and operational limitations.
