# Abyssal Engine 1.17.4 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

All 42 Python unit tests passed on Linux x86-64. Headless Godot UI, platform input (340 assertions), controller UI (67 assertions) and localization checks passed. All 906 engine texts and 14 translation catalogs passed their consistency and font-coverage checks.

UI checks cover simultaneous fading notices and duplicate messages, wrapped notices in portrait layouts, rereading radio dialogue without repeating completion, the saved pilot portrait, optional wheel throttle and both S-key modes. With wheel throttle off, S retains graduated throttle-down input and gradual deceleration. With it on, S immediately stops forward motion, including during boost and autopilot; held and rebound keys were checked.

The interface was rendered on Linux with OpenGL Compatibility at 1280×720 and 589×1280. The notice stack, wrapped messages, dialogue Back button, pilot profile and steering settings were checked at those sizes. These are viewport checks, not physical phone tests.

The Godot 4.7 release Web export was opened locally in Chromium at 1280×720. The title rendered with version 1.17.4, wheel throttle began disabled, and enabling and disabling it changed the S binding between Stop and Throttle down. No browser warnings or errors were reported during that check.

## Platform status

All six platform packages were rebuilt. Their archives were checked for integrity, allowlisted engine resources and bundled dependency hashes. The packaged Linux x86-64 executable started successfully, and its shipped game pack passed a startup and title check.

The Android APK was signed with the existing release key, checked for 16 KiB alignment and verified to request no network or external-storage permission. Its application ID is org.abyssal.engine and its version code is 61. Updates retain imported content and saves.

The packages were not played on Windows, macOS, Linux ARM64 or Android for this release. Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. The browser package uses WebGL 2. Physical phones, mobile browsers and physical gamepads were not exercised for this build.
