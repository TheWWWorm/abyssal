# Abyssal Engine 1.18.1 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

All 42 Python unit tests passed on Linux x86-64. Of the 25 headless Godot suites, 23 passed, including the engine UI, map, S.T.R.E.A.M., language and reference suites; the two ocean atmosphere and ocean options suites report the same failures as the 1.17.6 source and are unchanged by this release. All 1,104 engine texts and 14 translation catalogs passed consistency checks.

The reference check builds all 481 pages with an English and with a Russian JAR. It now also checks that a two-part creature is shown whole in the model viewer and that the web edition gives the search box its own row on phone screens. Every ship, creature and station picture was drawn with the Vulkan renderer and inspected; the web reference was checked in a desktop browser and at a 375 × 812 phone size without console errors.

The packaged Linux x86-64 executable passed a startup check. Its shipped game pack passed version, title, settings, map label and reference checks. The web package displayed the 1.18.1 main menu in a local Chromium browser without console warnings or errors; this browser check did not import game content.

The Android APK passed signature verification against the established release certificate and 16 KiB alignment checks. Its package is `org.abyssal.engine`, version 1.18.1, version code 65. It requests no network or storage permissions.

All six platform packages and the source archive passed inventory and SHA-256 checks. Source files match the publication allowlist, and package documentation is consistent across the desktop and web archives.

## Platform status

The browser build uses WebGL 2. Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. Native Windows, macOS, Linux ARM64 and Android gameplay was not exercised for this release. Physical phones, mobile browsers and physical gamepads were not tested for this build. Source UI checks do not establish device performance.
