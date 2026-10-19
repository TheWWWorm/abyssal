# Abyssal Engine 1.18.3 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

All 42 Python unit tests passed on Linux x86-64. Of the 25 headless Godot suites, 23 passed, including the engine UI, map, S.T.R.E.A.M., language and reference suites; the two ocean atmosphere and ocean options suites report the same failures as the 1.18.2 source and are unchanged by this release. All 1,109 engine texts and 14 translation catalogs passed consistency checks.

The coordinate suite checks that each escort freighter is solid exactly where its hull is, and that manual roll leaves the hull at the angle it was given, does nothing while switched off, and works from a gamepad stick given the Roll role. In the windowed game the submarine came to rest 12.6 m from a freighter's side and 12.7 m from its bow, which is its own collision radius; after a S.T.R.E.A.M. arrival the shot played to the end and a waiting briefing opened 2.5 s later in five of five runs, and the briefing after a departure opened 2.5 s after the departure shot. Roll right lowered the hull's right side, as expected. The reference suite builds every page without failures; the hosted reference is unchanged in this release.

The packaged Linux x86-64 executable passed a startup check. Its shipped game pack passed version, title, settings, map label and reference checks. The web package displayed the 1.18.3 main menu in a local Chromium browser without console warnings or errors; this browser check did not import game content.

The Android APK passed signature verification against the established release certificate and 16 KiB alignment checks. Its package is `org.abyssal.engine`, version 1.18.3, version code 67. It requests no network or storage permissions.

All six platform packages and the source archive passed inventory and SHA-256 checks. Source files match the publication allowlist, and package documentation is consistent across the desktop and web archives.

## Platform status

The browser build uses WebGL 2. Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. Native Windows, macOS, Linux ARM64 and Android gameplay was not exercised for this release. Physical phones, mobile browsers and physical gamepads were not tested for this build. Source UI checks do not establish device performance.
