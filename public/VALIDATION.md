# Abyssal 1.20.1 — platform support

A compatible DEEP JAR must be supplied separately. Original game assets and data are not included.

## Validation

All 42 Python checks, seven Discord IPC checks and 25 of 26 Godot suites passed on Linux x86-64, both with the default renderer and in compatibility mode. The ocean atmosphere suite reports the existing cabin-light limits also present in 1.20.0; its errors are not new to this release. Touch control checks cover the separate throttle slider, its clearance from the fire button, mirroring and placement at landscape and upright sizes. Engine UI, gamepad menus, gameplay/session, open-world missions, coordinates, S.T.R.E.A.M., language, reference and Discord activity checks pass. All 1,114 engine texts and 14 translation catalogs passed consistency checks.

The depth arrow was checked at 1920 × 1080 with the Forward+, Mobile and Compatibility renderers. A build of these changes ran on a Retroid Pocket 5 (Android, Adreno 650, Vulkan Mobile renderer): the throttle slider, the reimport notice for an older import and the neutral water were checked there by hand.

The packaged Linux x86-64 executable passed startup and shipped-pack checks. The Android APK passed verification against the existing release certificate and 16 KiB alignment checks. Its package is org.abyssal.engine, version 1.20.1, version code 70. It requests no network or broad storage permissions. Inventory and SHA-256 checks cover all six platform packages and the source archive.

## Platform status

Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. Native Windows, macOS and Linux ARM64 gameplay was not exercised for this release. Mobile browsers and physical gamepads were not tested. Browser play requires WebGL 2. Discord integration is available only in desktop builds and requires the Discord desktop app with activity sharing enabled. Source checks do not establish device performance.
