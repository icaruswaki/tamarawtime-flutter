# Tamaraw Time — Flutter application

Native Flutter migration of `Tamaraw_Time_v9_1_Map_Fix.zip`. The original web source is preserved in `migration_source/` for reference; the app runs Dart widgets, not a WebView.

## Run

```powershell
flutter pub get
flutter run
```

Choose **Continue on this device** for a locally saved planner. This mode is separate from cloud accounts and does not collect research events. Local data is not encrypted; uninstalling or clearing app storage removes it.

For the existing Supabase account/database, the Flutter app uses the same project defaults as the web app. You can override either value at launch:

```powershell
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_KEY
```

Use your public publishable/anon key, never a service-role key. Email sign-in must be enabled. Confirm signup email, reset passwords through Supabase, then sign in. The existing `app_states.payload` and `activity_events` schema is retained, including class IDs, weekday numbers, 24-hour time strings, settings, tasks, and onboarding. Existing web accounts see their schedules after signing into the same project. For a new project only, use `migration_source/schema.sql`; do not recreate an existing research database.

## Implemented

- Dashboard with next weekly class, get-ready/leave/arrival recommendations and countdown using Philippine calendar time.
- Add, edit, and delete classes with native AM/PM time pickers and campus selection.
- Commute class/mode selection, editable journey/preparation/buffer values and saved defaults.
- Interactive OpenStreetMap, foreground GPS, walking/driving route geometry and automatic trip estimate.
- Metro Manila jeepney relation discovery, ordered boarding/alighting stops, route selection and pedestrian connectors. No invented stops, live transit ETA, fares, or service availability.
- Four themes, five-step guide, JSON backup copied to clipboard, cloud refresh, and confirmed planner reset.
- Supabase signup/login, remembered email, password reset, session persistence, serialized cloud writes and the original named research events. Coordinates are only held in memory and sent to external routing services, never written into planner payloads or research events.
- Separate opt-in device storage for use before configuring Supabase.

Walking/driving estimates are applied to the open commute planner. Save as default commute to use those minutes on the dashboard. Changing destination/mode clears route overlays; transit always uses your editable total journey estimate. GPS stops when leaving the commute screen or backgrounding the application. It does not restart automatically after returning from the background.

## Mobile builds

Android internet and foreground location permissions and iOS location purpose text are included.

```powershell
flutter build apk --debug
```

An Android SDK is required. Connect a phone with USB debugging enabled, then run `flutter devices` and `flutter run -d DEVICE_ID`. On this workstation Flutter is installed, but Android SDK is missing, so an APK could not be built here. iOS builds require macOS/Xcode. App Store/Play Store signing, production application identifiers, and launcher icon generation remain release setup tasks; the original logo is included inside the app.

Maps require internet. Public tile, routing, Overpass, and route-detail services can fail or rate-limit. Test GPS permissions, background/foreground behavior, actual routes, and Supabase signup/load/save on a physical phone before distribution. No backend changes or deployments were performed.

## Checks

```powershell
flutter analyze
flutter test
```

Tests cover weekly/AM-PM time handling, persistence and payload compatibility, transit classification, and adding a class through the UI.

## Styling from the web app

`lib/src/theme.dart` translates the original `migration_source/styles.css` into native Flutter themes and widgets: exact Forest/Ocean/Golden Hour/Midnight palettes, cream page backgrounds, rounded bordered cards, form controls, gradient departure banner, gold accents, theme swatches, and responsive navigation. Screens wider than 1020 px use the original sidebar layout; phones use bottom navigation. Page entrance animations respect the device reduced-motion preference.

Use a hot restart after updating the app. Color schemes are selected in Settings and applied with Save settings. CSS files are reference material; Flutter renders the matching styles through Dart widgets.

`flutter test` includes phone/desktop layout checks. On this workstation, `flutter test --dart-define=STYLE_PREVIEW=true test/style_preview_test.dart` also writes phone and desktop previews to `build/style-preview-390.png` and `build/style-preview-1440.png`.
