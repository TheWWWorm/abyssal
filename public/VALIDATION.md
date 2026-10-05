# Abyssal Engine 1.17.6 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

All 42 Python unit tests passed on Linux x86-64. The headless Godot UI and native map/S.T.R.E.A.M. suites passed. All 906 engine texts and 14 translation catalogs passed consistency checks.

Map checks cover 360 combinations of language, chart size, zoom and pan. They check label spacing, marker and scale clearance, stable placement, ambiguous neighboring markers, hover names and the original adjacent-station case. Full map views were inspected with the OpenGL Compatibility renderer. The map's header Back control was checked for return to flight and docked stations; Portuguese action labels fit the tested desktop and touch layouts.

The packaged Linux x86-64 executable passed a startup check. Its shipped game pack passed version, title, settings and adjacent-station label checks. The web package displayed the 1.17.6 main menu in a local Chromium browser at 1280 × 720 without console warnings or errors; this browser check did not import game content.

The Android APK passed signature verification against the established release certificate and 16 KiB alignment checks. Its package is `org.abyssal.engine`, version 1.17.6, version code 63. It requests no network or storage permissions.

All six platform packages and the source archive passed inventory and SHA-256 checks. Source files match the publication allowlist, and package documentation is consistent across the desktop and web archives.

## Platform status

The browser build uses WebGL 2. Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. Native Windows, macOS, Linux ARM64 and Android gameplay was not exercised for this release. Physical phones, mobile browsers and physical gamepads were not tested for this build. Source UI checks do not establish device performance.
