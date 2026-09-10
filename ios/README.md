# SkincareSync for iOS

Native SwiftUI client for the SkincareSync ingredient interaction engine. It
talks to the FastAPI backend in this repository; nothing about products,
ingredients or interaction rules lives on the device.

- Swift 6, SwiftUI, Observation, structured concurrency
- iOS 17.0 and later, iPhone
- No third-party dependencies

## Open and run

```bash
open ios/SkincareSync.xcodeproj
```

Select the shared **SkincareSync** scheme and an iPhone simulator, then Run.
The project uses Xcode 16+ file-system-synchronized groups, so any file added
under `ios/SkincareSync/` or `ios/SkincareSyncTests/` is picked up
automatically; there is no per-file bookkeeping in `project.pbxproj`.

Start the backend first (from the repository root):

```bash
source venv/bin/activate
uvicorn skincaresync.api:app --host 127.0.0.1 --port 8000
```

Or `./scripts/dev.sh`, which also starts the web frontend.

## API configuration

The base URL is a build setting, `API_BASE_URL`, read into `Info.plist` as
`APIBaseURL` and parsed by `APIConfiguration` at launch.

| Configuration | File | Default | Transport |
| --- | --- | --- | --- |
| Debug | `Config/Debug.xcconfig` | `http://127.0.0.1:8000` | `NSAllowsLocalNetworking` only (`Config/Info-Debug.plist`) |
| Release | `Config/Release.xcconfig` | *(empty)* | ATS default, HTTPS required (`Config/Info-Release.plist`) |

- **Debug on the simulator** works out of the box against the local backend.
- **Debug on a device** on the same Wi-Fi: change the value in
  `Config/Debug.xcconfig` to your Mac's LAN address, e.g.
  `API_BASE_URL = http:/$()/192.168.1.20:8000`. The `$()` keeps xcconfig from
  reading `//` as a comment. Make sure the backend binds to `0.0.0.0`.
- **Release** refuses to start until `API_BASE_URL` is an `https://` URL. Set
  it in `Config/Release.xcconfig`, or pass it on the command line:

  ```bash
  xcodebuild -project ios/SkincareSync.xcodeproj -scheme SkincareSync \
    -configuration Release API_BASE_URL='https://api.example.com' build
  ```

  A misconfigured release build shows a "Backend not configured" screen
  instead of guessing a host.

Signing: `DEVELOPMENT_TEAM` is intentionally empty in `Config/Shared.xcconfig`.
Simulator builds need none. For a device, set your team in Xcode's Signing &
Capabilities tab or pass `DEVELOPMENT_TEAM=XXXXXXXXXX` to `xcodebuild`.

## Authentication

The app uses a normal `URLSession` with cookie storage. `GET /api/auth/session`
runs at launch; a signed-in user's `csrf_token` is retained and the value of
the `skincaresync_csrf` cookie (which the backend reissues on some calls) is
sent as `X-CSRF-Token` on every non-GET request. Logging out always clears the
local cookies, even when the backend cannot be reached.

**Social sign-in is not offered in the app.** `/api/auth/oauth/{provider}/start`
is a top-level browser flow whose callback sets cookies on the API origin and
then redirects to the *web app* (`APP_BASE_URL/signin`). Those cookies land in
the browser's jar, not the app's `URLSession`, and there is no app-scheme or
Universal Link callback registered with the providers. Supporting it natively
would need a new callback contract on the server and provider configuration,
so the app omits the buttons rather than invent one. Linked identities from
the web app are still listed under Security and can be disconnected.

## Where things are

```text
ios/
  SkincareSync.xcodeproj          hand-written project, shared scheme
  Config/                         xcconfigs and the two Info.plist variants
  SkincareSync/
    App/                          entry point, dependency wiring, tab root
    DesignSystem/                 palette, type scale, spacing, severity presentation, components
    Core/Networking/              APIClient protocol, LiveAPIClient, MockAPIClient, endpoints, errors
    Core/Persistence/             DraftStore (Codable JSON file in Application Support)
    Models/                       Codable models mirroring the backend
    Features/Home|Routine|Report|Ingredients|Account|Scanner
    Resources/Fixtures/           real responses captured from the backend, used by previews and tests
  SkincareSyncTests/              Swift Testing suites
```

## Tests

```bash
xcodebuild test -project ios/SkincareSync.xcodeproj -scheme SkincareSync \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

`LiveBackendTests` is skipped by default. To run it against a local
development backend (it registers a throwaway account and runs an analysis),
compile the tests with the `SKINCARESYNC_LIVE_TESTS` condition:

```bash
xcodebuild test -project ios/SkincareSync.xcodeproj -scheme SkincareSync \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) SKINCARESYNC_LIVE_TESTS'
```

Set `SKINCARESYNC_LIVE_BASE_URL` in the scheme's test environment to point the
live suite somewhere other than `http://127.0.0.1:8000`.

## Debug launch arguments

Debug builds accept a few arguments for manual verification. None of them
apply implicitly; the fixture client shows a persistent "Fixture data" banner.

| Argument | Effect |
| --- | --- |
| `-SkincareSyncMockAPI` | Use the fixture-backed `MockAPIClient` (signed in) |
| `-SkincareSyncMockSignedOut` | With the mock, start signed out |
| `-SkincareSyncStartTab home\|routine\|ingredients\|account` | Initial tab |
| `-SkincareSyncOpenReport` | With the mock, open the fixture report immediately |
| `-SkincareSyncOpenIngredient <id>` | Push an ingredient detail immediately |
| `-SkincareSyncOpenEditor` | Open the product editor for the first morning product |

Example:

```bash
xcrun simctl launch booted com.skincaresync.app -SkincareSyncMockAPI -SkincareSyncOpenReport
```

## Barcode scanning

VisionKit's `DataScannerViewController` reads EAN, UPC, Code 128/39/93, ITF-14,
QR and Data Matrix codes and calls `/api/products/code` with the payload. The
simulator and devices without the scanner fall back to typing the code, which
is always available. Camera access is never required to add a product.

## Local data

The skin profile and both routines are saved as JSON in
`Application Support/SkincareSync/routine-draft.json` and restored on launch.
Reports are kept in memory for the session. Nothing is synced to the account;
the backend has no saved-routine endpoint.
