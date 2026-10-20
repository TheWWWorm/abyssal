# Abyssal 1.20.0 — platform support

A compatible DEEP JAR must be supplied separately. Original game assets and data are not included.

## Validation

All 42 Python checks, seven Discord IPC checks and 25 of 26 Godot suites passed on Linux x86-64, both with the default renderer and in compatibility mode. The ocean atmosphere suite reports the existing cabin-light limits also present in 1.19.0; its errors are not new to this release. The enhanced sky-light checks run on a GPU and pass with the new light columns. Engine UI, gamepad menus, gameplay/session, open-world missions, coordinates, S.T.R.E.A.M., language, reference and Discord activity checks pass. All 1,111 engine texts and 14 translation catalogs passed consistency checks.

Enhanced lighting was compared at 1920 × 1080 on the Very high preset across five regions at 6000, 9000, 22500 and 33000 depth, near stations and while boosting; Classic lighting was compared against a recording of the original game.

The packaged Linux x86-64 executable passed startup and shipped-pack checks. The Android APK passed verification against the existing release certificate and 16 KiB alignment checks. Its package is org.abyssal.engine, version 1.20.0, version code 69. It requests no network or broad storage permissions. Inventory and SHA-256 checks cover all six platform packages and the source archive.

## Platform status

Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. Native Windows, macOS, Linux ARM64 and Android gameplay was not exercised for this release. Physical phones, mobile browsers and physical gamepads were not tested. Browser play requires WebGL 2. Discord integration is available only in desktop builds and requires the Discord desktop app with activity sharing enabled. Source checks do not establish device performance.
