# Mobility and punctuality upgrade

This updates the existing Tamaraw Time application. Its Supabase accounts,
Remember me, recovery/change-password flows, logout confirmation, device planner,
weekly class records, calendar, tutorial, four color schemes and existing research
event names remain. No student schedule migration or reset is required.
Tasks & Deadlines has not been added.

## Interface and files

| Files | Change |
| --- | --- |
| `lib/src/theme.dart` | Material 3 design system, quieter surfaces, green/gold branding, readable typography, light/dark logo treatment, adaptive navigation and animated theme colors. Uses Material/platform fonts without a runtime font download. |
| `lib/main.dart` | Connects shared journey state to the dashboard, next-class changes, preferences and existing navigation. Adds an explicit manual fallback preference. |
| `lib/src/punctuality_overview.dart` | Next-class card, campus/room, class countdown, preparation, arrival buffer, route duration, departure guidance and supported punctuality states. |
| `lib/src/journey_widgets.dart` | Reusable cards/headings, route comparison cards, provider itinerary steps, live clock/countdowns and public Google Maps/Sakay.ph links. |
| `lib/src/class_calendar.dart` | Matching calendar styling, selected-day class count and reduced-motion-aware date transitions; existing recurrence/CRUD remains. |
| `lib/src/journey.dart` | Typed provider itineraries and departure calculations; no guessed transit steps, fares or timings. |
| `lib/src/journey_controller.dart` | Foreground location, permission state, in-memory routes, automatic refresh, stale-request protection and shared selections. |
| `lib/src/journey_service.dart` | Authenticated Supabase function adapter and separately attributed OpenStreetMap road fallback. |
| `lib/src/planner.dart` | Owns transient journey state without serializing coordinates or route history into student payloads. Clears it on logout. |
| `lib/src/commute.dart` | Map-first planning, origin/destination controls, campus/map/coordinate origins, draggable route details, route selection and optional manual timing. Preserves mapped jeepney discovery and walking connectors. |
| `lib/src/map_configuration.dart`, `maps_loader*.dart`, `google_journey_map.dart` | Google Maps readiness, browser loading, native map, markers, polylines, camera fitting and attribution padding. |
| `lib/src/routing.dart` | Preserves OSM road/jeepney helpers; removes inferred rail speeds and scaled driving routes masquerading as transit estimates. |
| `supabase/functions/commute-routes/` | Authenticated, origin-restricted Routes API proxy and testable request/handler implementation. |
| `supabase/migrations/202611080001_route_request_limits.sql` | Additive atomic quota counter, separate from schedules and activity records. |
| Android/iOS configuration and `web/index.html` | Restricted map-key configuration and browser loader. |
| `tool/prepare_launcher_icon.dart`, `assets/generated/`, platform icon resources | Padded launcher artwork generated from the supplied logo, followed by `flutter_launcher_icons`. Original artwork is unchanged. |
| `test/journey_test.dart`, `test/punctuality_widget_test.dart`, `test/routes_backend.test.mjs` | Departure, provider parsing, failures, permissions, throttling, cancellation, route guidance, layout, logo, authentication and quota tests with mocked responses. |

## Behavior and transport coverage

Dependency changes are limited to making the already-installed `url_launcher`
(`^6.3.2`) a direct runtime dependency for public directions links, and `image`
(`^4.12.0`) a direct development dependency for launcher padding. Google Maps,
geolocator, Supabase, HTTP, table_calendar and flutter_launcher_icons were already
present and are reused. No additional state-management, font or notification
package was introduced.

On entering a planner with classes, the dashboard selects the next class and its
campus/mode. If location permission was already granted, it restores foreground
location and requests a route. On first use, choose **Use my location** or
**Start GPS** to grant permission explicitly. After denial, the app directs the
student to system settings rather than repeatedly opening permission prompts.

An origin may also be a campus, a map point or labelled coordinates. Address
search/geocoding and saved origin history are not implemented. Coordinates stay
in memory and are sent only to the selected routing/map services. They are not
included in student payloads, research events, quota rows or application logs.

Tracking stops on Home/Commute when disabled, when navigating to Schedule or
Settings, when leaving the planner, and when backgrounding the app. Background
location collection and departure notifications are not implemented; this project
had no notification infrastructure to preserve.

Automatic requests are debounced, have a 45-second minimum interval, refresh
after substantial movement (250 m), and refresh stale estimates (five minutes or
a missed scheduled boarding). Class, campus, mode and buffer changes invalidate
the corresponding estimate. Explicit refresh is available. Obsolete responses
cannot overwrite a newer destination or account; an already-running upstream
request may still consume provider quota.

| Mode | Data and limitations |
| --- | --- |
| Walking / Driving | Google Routes when Maps and the authenticated proxy are configured. Otherwise a real OSM road estimate, explicitly marked as lacking live traffic. |
| Transit | Google-returned transit itineraries only. No driving-time substitute when unavailable. |
| Bus / UV | Google BUS preference. UV Express coverage is not assumed. |
| Train / LRT / MRT | Google RAIL preference. Returned services determine the actual mode/line; preferences are not guarantees. |
| Jeepney | Existing OSM mapped candidates and walking connectors. Current operation is unverified; there is no invented total ETA, fare, availability or multi-jeepney transfer. |

Cards show only returned fare, walking distance, stop names, headsigns, stop
counts and schedule details. Fastest/fewest-transfer/least-walking labels compare
the returned alternatives. Missing information stays absent. Public directions
links are optional fallbacks; there are no private Sakay.ph API calls.

The base calculation is:

```text
leave = class start - provider journey duration - arrival buffer
prepare = leave - preparation duration
```

An earlier provider timetable departure takes precedence when necessary to catch
the selected service. Missing/stale ETAs do not produce a lateness status. A
manual fallback is explicitly labelled and does not become a Google ETA. Traffic
conditions and transit coverage must be checked against live provider responses.

## Google Cloud and client Maps setup

Google-backed routes are enabled only when the Google map is ready and the user
has an authenticated Supabase session. Without that setup, OSM and honest
unavailable states remain usable. No Google credentials were present or tested
for this update.

1. Enable billing and the required Maps SDK for each target platform, plus the
   Routes API, in your Google Cloud project.
2. Use separate **restricted client Maps keys** and a **server Routes key**.
   Restrict browser keys to your HTTP referrers and Maps JavaScript API, Android
   keys to the actual application ID and signing SHA-1, and iOS keys to the actual
   bundle ID. Configure API restrictions and project quotas for the server key.
3. Keep the Routes key in Supabase secrets only. Never pass it through Flutter
   defines, platform manifests, browser JavaScript or student settings.

Google Maps for Flutter setup is documented at
[Google's configuration guide](https://developers.google.com/maps/flutter-package/config).
The request adapter follows the supported
[Routes transit modes and preferences](https://developers.google.com/maps/documentation/routes/transit-route).

### Chrome

```powershell
flutter pub get
flutter run -d chrome --web-port 7357 --dart-define=GOOGLE_MAPS_WEB_KEY=YOUR_RESTRICTED_BROWSER_MAPS_KEY
```

The key is necessarily visible to the browser and must be referrer/API restricted.
Use HTTPS outside localhost for Web geolocation. Include the origin
`http://localhost:7357` in the Edge Function allow list and the relevant callback
URLs in Supabase Auth's redirect allow list (see the account setup guide).

Without a configured Google map:

```powershell
flutter run -d chrome --web-port 7357
```

### Android and APK

The manifest reads an environment/Gradle Maps key. The existing application ID is
`com.example.tamaraw_time`; restrict the key to the ID/certificate you actually
build, or deliberately configure a production ID first.

```powershell
$env:MAPS_ANDROID_KEY = 'YOUR_RESTRICTED_ANDROID_MAPS_KEY'
flutter devices
flutter run -d YOUR_ANDROID_DEVICE_ID --dart-define=GOOGLE_MAPS_ENABLED=true
flutter build apk --debug --dart-define=GOOGLE_MAPS_ENABLED=true
```

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.
For an OSM build that needs no Maps key:

```powershell
flutter build apk --debug
```

For distribution, configure a production application ID, release keystore and
signing configuration, then build with `flutter build apk --release` (plus the
Maps define if configured). The existing release Gradle configuration uses debug
signing and is not a production signing setup. An APK build does not validate
real GPS behavior, Google billing, API-key restrictions or email callbacks.

### iOS and other native desktops

On macOS/Xcode, create the ignored file `ios/Flutter/Secrets.xcconfig` with
`GOOGLE_MAPS_API_KEY = YOUR_RESTRICTED_IOS_MAPS_KEY`. Debug/Release configuration
includes it optionally; Info.plist/AppDelegate pass it to the Maps SDK. Enable
the widget with `--dart-define=GOOGLE_MAPS_ENABLED=true` only after configuration.
iOS binary builds were not performed on Windows.

Native Windows/Linux/macOS use the existing OSM map. The current Google Maps
Flutter integration targets Android, iOS and Web; it is not a native desktop map
implementation. Desktop browsers can use the Google Web setup above.

## Supabase Edge Function setup

No Edge Function was deployed and no SQL was executed against your project.

1. Install the Supabase CLI and authenticate to your existing project.
2. Review and apply **only**
   `supabase/migrations/202611080001_route_request_limits.sql`, either through the
   SQL Editor or your normal migration workflow. It creates a quota table/function
   and never modifies `app_states` or `activity_events`. Do not rerun the historical
   `migration_source/schema.sql` against existing student data.
3. Copy `supabase/functions/.env.example` to the ignored `.env.local` beside it.
   Set the server Routes key and exact allowed Web origins (scheme/host/port,
   without a trailing slash). Managed Supabase URL/public-key environment values
   are used for user verification. No service-role key is needed.
4. Upload secrets and deploy:

```powershell
supabase login
supabase secrets set --env-file supabase/functions/.env.local --project-ref YOUR_PROJECT_REF
supabase functions deploy commute-routes --project-ref YOUR_PROJECT_REF --no-verify-jwt
```

Legacy gateway JWT verification is disabled in `supabase/config.toml`. Each
request is still explicitly authenticated with `auth.getUser()` using the supplied
user bearer token, before consuming quota or calling Google. The handler rejects
unapproved browser origins, unsupported methods/modes and invalid coordinates.
It uses a fixed upstream URL, a scoped response field mask and a timeout. See
[Supabase's function authentication guide](https://supabase.com/docs/guides/functions/auth).

The atomic database quota is **10 requests per minute and 100 per UTC day per
user**, shared across Edge instances. Anonymous access to the quota table is
revoked. Its rows contain counters and a user ID, not location data. If the quota
store is unavailable, the proxy fails closed. Set appropriate Google project
quotas as an additional project-wide limit. Responses are private/no-store;
route data is held only in foreground memory for the short refresh window.

Google outages, missing configuration and missing transit coverage display:
**Live travel estimates are currently unavailable.**

## Icons and validation

Regenerate icons without modifying the supplied artwork:

```powershell
dart run tool/prepare_launcher_icon.dart
dart run flutter_launcher_icons
```

The first step centers the original PNG with padding for launcher masks. The
second generates Android adaptive/legacy, iOS, Web favicon/PWA, Windows and macOS
icons through the existing package. Header logos use `BoxFit.contain` directly
from `assets/images/tamaraw-logo.png`, with a light backing in dark themes.

Validation completed:

- `flutter pub get` and Dart formatting completed.
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: all **44 tests passed**.
- `node --test test/routes_backend.test.mjs`: all **8 tests passed**.
- `flutter build web --no-pub --no-wasm-dry-run`: successful.
- `flutter build apk --debug --no-pub`: successful; installable artifact at
  `build/app/outputs/flutter-apk/app-debug.apk`. This default build uses OSM
  because no Google client/server keys were configured.
- Launcher-icon generation completed for Android, iOS, Web, Windows and macOS.
- Phone/desktop previews were generated and inspected; responsive tests cover
  phones, tablets, desktop widths and double-size text, including the route UI.
- The thin Edge entry point passed TypeScript-stripping/JavaScript syntax checks
  using Node. Its request/handler logic is exercised by the eight mocked tests.
- `flutter doctor -v`: Android SDK 36, licenses, Chrome and Windows tools found.

Real Google API calls, SQL deployment, Supabase Edge/Deno execution and
physical-device GPS remain deployment checks; mocked tests do not establish live
transit coverage. iOS builds require macOS/Xcode. These checks do not verify
production key restrictions, Google billing or current jeepney operation.
