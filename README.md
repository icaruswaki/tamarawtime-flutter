# Tamaraw Time — Flutter application

Native Flutter migration of `Tamaraw_Time_v9_1_Map_Fix.zip`. The original web source is preserved in `migration_source/` for reference; the app runs Dart widgets, not a WebView.

The account, calendar and responsive-layout upgrade is documented in
[Account and calendar setup](docs/account-calendar-upgrade.md), including recovery
redirect URLs, Remember me behavior, dependencies, and validation limits.

The current [mobility setup guide](docs/mobility-upgrade.md) covers the redesigned
dashboard/map, automatic provider estimates, protected Google Routes proxy,
transport coverage, map keys, launcher icons and Chrome/Android/APK commands.

The [transit and fare integration guide](docs/transit-integration.md) covers the
September 28, 2026 LTFRB reference calculator, opt-in student estimates, verified
ride-distance requirements, departure guidance and optional historical GTFS
exploration. Missing classifications or distances display **Fare not available**.

The [rail and jeepney V2 guide](docs/rail-jeepney-v2.md) covers **Commute →
Stations & routes**: all 51 LRT-1/LRT-2/MRT-3 stations, six line termini, three
walking interchanges, and the imported Sakay historical route/stop directories.
Historical records never establish current operation, fares or arrivals.

## Run

```powershell
flutter pub get
flutter run
```

Choose **Continue on this device** for a locally saved planner. This mode is separate from cloud accounts and does not collect research events. Local data is not encrypted; uninstalling or clearing app storage removes it.

For the existing Supabase account/database:

```powershell
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_KEY
```

Use your public publishable/anon key, never a service-role key. The existing public project configuration remains the default; the defines above override it. Email sign-in must be enabled. Confirm signup email in your browser, then return to the app and sign in. The existing `app_states.payload` and `activity_events` schema is retained, including class IDs, weekday numbers, 24-hour time strings, settings, and onboarding. Existing web accounts see their schedules after signing into the same project. For a new project only, use `migration_source/schema.sql`; do not recreate an existing research database.

## Implemented

- Dashboard with next weekly class, get-ready/leave/arrival recommendations and countdown using Philippine calendar time.
- Monthly class calendar with weekly markers, selected-day classes, and optional multiple weekdays. Add, edit, and delete classes with native AM/PM time pickers and campus selection.
- Commute class/mode selection, editable journey/preparation/buffer values and saved defaults.
- Interactive OpenStreetMap, foreground GPS, walking/driving route geometry and automatic trip estimate.
- Metro Manila jeepney relation discovery, ordered boarding/alighting stops, route selection and pedestrian connectors. No invented stops, live transit ETA, fares, or service availability.
- Four themes, visual tutorial, JSON backup copied to clipboard, cloud refresh, and confirmed planner reset.
- Supabase signup/login, Remember me, logout confirmation, complete password recovery and Settings password changes. Serialized cloud writes and original research events remain. Coordinates are held in memory and sent to external routing services, never written into planner payloads or research events.
- Separate opt-in device storage for use before configuring Supabase.

Provider estimates now update Home and Commute together, with departure/preparation calculations and supported punctuality states. Configured Google routes include structured transit guidance; OSM road estimates remain separately labelled. Missing transit data stays unavailable instead of being replaced by a driving-time multiplier. Manual fallback timing is explicit. Changing destination/mode invalidates old routes. GPS stops when disabled, entering Schedule/Settings, leaving the planner or backgrounding the application. It does not restart automatically after returning from the background.

## Mobile builds

Android internet and foreground location permissions and iOS location purpose text are included.

```powershell
flutter build apk --debug
```

An Android SDK is required. Connect a phone with USB debugging enabled, then run `flutter devices` and `flutter run -d DEVICE_ID`. The current workstation has an Android SDK and accepted licenses. iOS builds require macOS/Xcode. App Store/Play Store signing and production application identifiers remain release setup tasks. Launcher icons are generated from the updated green-and-gold artwork; Google Maps and Routes setup is documented in the mobility guide.

Maps require internet. Public tile, routing, Overpass, and route-detail services can fail or rate-limit. Test GPS permissions, background/foreground behavior, actual routes, and Supabase signup/load/save on a physical phone before distribution. The Google Routes proxy and additive quota migration are prepared locally; no backend deployment or remote database changes were performed.

## Checks

```powershell
flutter analyze
flutter test
```

Tests cover weekly/AM-PM time handling, persistence and payload compatibility, transit classification, and adding a class through the UI.

## Styling from the web app

`lib/src/theme.dart` translates the original `migration_source/styles.css` into native Flutter themes and widgets: Forest/Ocean/Golden Hour/Midnight palettes, cream page backgrounds, rounded bordered cards, form controls, gradient departure banner, gold accents, and theme swatches. Navigation uses a bottom bar below 600 logical pixels, a rail at 600–1023, and the original sidebar at 1024 and above. Page entrance and calendar animations respect the device reduced-motion preference.

Use a hot restart after updating the app. Color schemes are selected in Settings and applied with Save settings. CSS files are reference material; Flutter renders the matching styles through Dart widgets.

`flutter test` includes phone/desktop layout checks. On this workstation, `flutter test --dart-define=STYLE_PREVIEW=true test/style_preview_test.dart` also writes phone and desktop previews to `build/style-preview-390.png` and `build/style-preview-1440.png`.

## Optional scheduled-transit router

The [Sakay source and data audit](docs/sakay-otp-integration.md) explains what
the original web frontend contributed and which current data is still missing.
The [OTP Windows/Docker guide](backend/otp/README.md) provides a pinned OTP 2.8.1
GraphQL gateway and an opt-in Flutter adapter (`OTP_PLANNER_URL`). The engine
has not been started here: Docker and usable current GTFS/OSM inputs are missing.
Historical Sakay service dates are not extended. Missing transit ETAs remain
explained and independent of the working OSRM walking/driving estimates.
