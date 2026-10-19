# Abyssal Engine 1.19.0 — platform support

A compatible DEEP JAR must be supplied separately. Original game assets and data are not included.

## Validation

All 42 Python checks, seven Discord IPC checks and 25 of 26 headless Godot suites passed on Linux x86-64. The ocean atmosphere suite reports the existing cabin-light limits also present in 1.18.3; its errors are not new to this release. Engine UI, gamepad menus, gameplay/session, coordinates, S.T.R.E.A.M., language, reference and Discord activity checks pass. All 1,111 engine texts and 14 translation catalogs passed consistency checks.

Discord IPC checks use synthetic local peers, including the actual Godot-to-Node process pipe, reconnects, update coalescing and exit cleanup. Live Discord account display has not been verified. Profile artwork uses the application's configured Discord assets.

The packaged Linux x86-64 executable passed startup and shipped-pack checks. Windows PE icon resources match the approved ICO frames, and the macOS bundle contains the generated ICNS. Android launcher, adaptive, themed and system startup icons are checked in the APK. A local Chromium browser displayed the branded loading screen and reached the main menu; this browser check did not import a JAR.

The Android APK passed verification against the existing release certificate and 16 KiB alignment checks. Its package is org.abyssal.engine, version 1.19.0, version code 68. It requests no network or broad storage permissions. Inventory and SHA-256 checks cover all six platform packages and the source archive.

## Platform status

Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. Native Windows, macOS, Linux ARM64 and Android gameplay was not exercised for this release. Physical phones, mobile browsers and physical gamepads were not tested. Browser play requires WebGL 2. Discord integration is available only in desktop builds and requires the Discord desktop app with activity sharing enabled. Source checks do not establish device performance.
