# Abyssal Engine 1.18.2 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

All 42 Python unit tests passed on Linux x86-64. Of the 25 headless Godot suites, 23 passed, including the engine UI, map, S.T.R.E.A.M., language and reference suites; the two ocean atmosphere and ocean options suites report the same failures as the 1.18.1 source and are unchanged by this release. All 1,104 engine texts and 14 translation catalogs passed consistency checks.

The coordinate suite now also checks that each freighter in an escort contract blocks only its own hull. A measurement around the escort convoy confirms that the submarine is stopped at most 87 m from a freighter's bow or stern and 32 m from its side, where it was previously stopped up to 162 m and 52 m away. The reference suite builds every page without failures; the hosted reference is unchanged in this release.

The packaged Linux x86-64 executable passed a startup check. Its shipped game pack passed version, title, settings, map label and reference checks. The web package displayed the 1.18.2 main menu in a local Chromium browser without console warnings or errors; this browser check did not import game content.

The Android APK passed signature verification against the established release certificate and 16 KiB alignment checks. Its package is `org.abyssal.engine`, version 1.18.2, version code 66. It requests no network or storage permissions.

All six platform packages and the source archive passed inventory and SHA-256 checks. Source files match the publication allowlist, and package documentation is consistent across the desktop and web archives.

## Platform status

The browser build uses WebGL 2. Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. Native Windows, macOS, Linux ARM64 and Android gameplay was not exercised for this release. Physical phones, mobile browsers and physical gamepads were not tested for this build. Source UI checks do not establish device performance.
