# Account and calendar upgrade

This extends the existing Flutter app. Supabase Auth and the `app_states.payload`
and `activity_events` tables remain in use, alongside the separate device planner
stored in `tamaraw_local`. No database migration or data reset is required. The
logo, favicon, four themes, onboarding, departure calculations, foreground GPS,
OpenStreetMap routes, full-screen route planner, and public-transport discovery
remain. Tasks & Deadlines has not been added.

## Features and files

- `lib/main.dart`: integrates the account controls, logout confirmation, recovery
  screen, Account Security in Settings, calendar, and multi-weekday class editor.
  Environment defines can override the existing public Supabase configuration.
- `lib/src/account.dart`: SDK-backed Remember me storage policy, auth-state
  coordination, validated callback handling, neutral recovery requests, password
  updates, reauthentication and sign-out. Passwords never enter planner payloads,
  preferences or research logs.
- `lib/src/account_widgets.dart`: accessible password visibility controls,
  recovery-email dialog and confirmed-password forms with validation, busy states
  and safe error messages. Settings changes verify the current password and
  support the provider's emailed reauthentication nonce when requested.
- `lib/src/auth_url_cleanup*.dart`: removes handled auth credentials from the
  browser address bar, using a conditional Web implementation.
- `lib/src/class_calendar.dart`: month navigation, today's date, selected date,
  recurring class markers and the selected day's schedule. Calendar and schedule
  use two columns when the available width and text size allow it.
- `lib/src/planner.dart`: understands legacy `day` records and optional
  `weekdays`, formats AM/PM labels, and keeps departure calculations consistent
  with multiple weekdays. Saves capture their original account/device target;
  clearing signed-out memory does not delete stored schedules.
- `lib/src/responsive.dart` and `lib/src/theme.dart`: shared breakpoints, bottom
  navigation, tablet rail, desktop sidebar, scrolling forms and adaptive columns.
- `lib/src/commute.dart`: responsive travel-mode fields and full-screen route
  controls that stack when accessibility text needs more room.
- Android/iOS manifest files: register `com.tamarawtime.app://auth-callback/` and
  allow AppLinks to handle callbacks without Flutter routing them a second time.
- `lib/src/routing.dart`: formatting and lint cleanup only; routing behavior is
  preserved.
- Tests cover storage policy, login preferences, logout, recovery, password
  changes, weekly recurrence, calendar CRUD, device saves and adaptive layouts.

## Dependencies

- New runtime dependency: `table_calendar: ^3.3.0`.
- `app_links: ^7.2.2` is now direct; it was already installed through Supabase.
- `yet_another_json_isolate: ^2.1.1` is a direct development dependency, already
  present through Supabase. It lets mocked SDK tests replace background JSON
  work without adding an isolate to Flutter's fake test clock.

## Remember me behavior

The preference defaults to enabled, preserving the existing restore behavior.
Only our boolean preference is saved by application code. Supabase still owns
session serialization, refresh, persistence and removal, using its existing SDK
storage implementation. We do not manually store passwords or tokens.

Unchecked logins use a custom SDK `LocalStorage` hook that suppresses persistent
session writes and removes any previously persisted SDK session. The active
session remains in SDK memory and can refresh while the app is open. On mobile
and desktop it ends when the app process ends. On Web it also ends on a page
reload; this is memory-only behavior, not browser `sessionStorage`. Browser
duplication, multiple tabs and provider session policies should be validated in
the deployment environment. Backgrounding a mobile app is not a logout.

Persistent logins use the provider's default storage, which is not a custom
encrypted credential vault. Explicit logout removes the current local session
and SDK persistence, retains the Remember me preference, clears the displayed
account data, and leaves server/device class records intact. It signs out this
device/session, not all the student's devices.

## Supabase configuration

1. Keep the existing tables and row-level security policies. Do not rerun the
   historical schema against an existing project.
2. Enable email/password authentication and configure production email delivery
   and recovery templates. The template must use Supabase's recovery confirmation
   link so the SDK can complete verification.
3. In **Authentication → URL Configuration**, set the production Site URL and add
   these allowed redirects as appropriate:
   - `com.tamarawtime.app://auth-callback/` for the supplied Android/iOS setup.
   - `http://localhost:7357/**` for local Web development.
   - `https://YOUR_HOST/**` for your actual Web host. Narrow production patterns
     to your deployed app path where possible, allowing callback query parameters.
4. Web defaults to its current scheme/host/port/path with `?recovery=1`. If hosting
   in a subdirectory, include that path in the allow list. You may override the
   redirect with `--dart-define=AUTH_REDIRECT_URL=...`; the callback must return
   to the app and match that scheme, host, port and path.
5. The recovery flow uses PKCE. Open the email link on the same device and in the
   same browser profile/app that requested it, so its SDK code verifier is
   available. Expired, reused or cross-device links require a fresh request.
6. Android and iOS scheme registration is included. Native Windows/Linux/macOS
   builds require their own OS protocol registration before email links can open
   the app; native desktop protocol installation is not performed by this change.
   A custom URL scheme alone is not a verified universal/app link. Configure
   verified HTTPS links for a production distribution if required.
7. Keep the server password policy aligned with or stricter than the existing
   six-character client minimum. Stronger server rules are enforced by Supabase.
   Secure password change/re-authentication challenges support emailed codes.

Supabase's Dart recovery flow sends the email with `resetPasswordForEmail`,
exchanges the verified callback through the SDK, and updates the user with
`updateUser`. The new-password form is shown before loading the planner, including
for cold-start callbacks. Successful recovery signs out and asks the student to
sign in with the new password. Settings changes keep the active account and class
data. See [password recovery](https://supabase.com/docs/reference/dart/auth-resetpasswordforemail)
and [updating users](https://supabase.com/docs/reference/dart/auth-updateuser).
See also [redirect URL configuration](https://supabase.com/docs/guides/auth/redirect-urls).

## Run and validate

```powershell
flutter pub get
flutter run
flutter run -d chrome --web-port 7357
flutter analyze
flutter test
```

To override the existing public project settings:

```powershell
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_KEY
```

Use a public publishable/anon key. Never embed a service-role key.

Validation executed for this update:

- `flutter pub get`: completed successfully.
- `dart format` on changed Dart files: completed successfully.
- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: all 29 tests passed.
- `flutter build web --no-pub --no-wasm-dry-run`: built `build/web` successfully.
- Android and iOS XML files parsed successfully; `git diff --check` passed.

Layout tests cover 320/390-pixel phones, a 768-pixel tablet, 1024/1440-pixel
desktop windows, landscape map resizing, all four themes, and double-size text,
including the full-screen route view.

Automated tests use mocked Supabase responses. They do not send email, change real
passwords, sign out real accounts, or modify production schedules. Before release,
manually validate actual email delivery, allow-listed redirect URLs, cold/warm
mobile callbacks, app/browser restarts with both Remember me choices, provider
expiry, explicit logout, and password policy/challenge behavior. Test live GPS
permissions, background/foreground tracking, routing services and saved schedules
on physical phones; confirm Chrome resizing and native desktop installation.
