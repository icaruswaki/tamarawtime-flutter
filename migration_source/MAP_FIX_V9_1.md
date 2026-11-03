# Tamaraw Time v9.1 — Leaflet map display fix

The map sometimes showed a 256-pixel vertical strip of tiles in the middle of an otherwise blank area. Leaflet was initialized while the animated commute content was changing dimensions. Its single delayed `invalidateSize()` call happened before animations completed.

Fix: monitor `#map-host` with `ResizeObserver`, react to page/card animation completion, and call Leaflet `invalidateSize({pan:false,animate:false})` at staged startup intervals. Disconnect these listeners on leaving the page. Preserve the native Leaflet tile size.

## Publish
Replace `app.js`, `styles.css`, and `index.html` from this package in your existing repository. Keep your configured `cloud-config.js` and existing `assets` folder. Optional: update other v9 files if your repository isn't yet on v9. Hard refresh after Pages deployment.

## GPS troubleshooting
GPS is off until the student clicks Start live GPS and grants permission. Location is accurate only if the browser/OS can resolve location. For GitHub Pages HTTPS is required.

## Verification
Run `node --check app.js`; browse to Commute Planner, resize the browser, navigate away and back, and inspect on mobile. Live map tile delivery depends on the third-party tile service.
