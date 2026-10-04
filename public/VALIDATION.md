# Abyssal Engine 1.17.3 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

All 42 Python unit tests passed on Linux x86-64, along with the Android importer and browser audio checks. The importer checks cover converter selection, startup failures, error reporting and transfer of converted content to the native app. All 903 engine texts and 14 translation catalogs passed their consistency check.

The headless Godot regression suite passed 22 of 23 checks. Platform input passed all 340 assertions, including dragging touch controls into the screen margins, selecting them there, saving and reloading their positions, responding to flight touches, resetting to the inset defaults and keeping controls visible after rotation. Gameplay, UI readability, controller UI, localization, content packaging, graphics settings, world streaming, terrain, travel and mission checks passed.

The ocean-atmosphere check reports 24 cabin-lighting assertions that also fail on unchanged 1.17.2 with the same imported content. This release therefore does not claim a completely passing regression suite.

Workshop price ranges and touch placement were visually checked on Linux with OpenGL Compatibility. Workshop details were checked at 1280×720, 2000×920 and 920×2000 with products requiring two and five ingredients. Touch controls were checked at 2340×1080 and 1080×2340, including positions beyond the default safe area. These are simulated viewport checks, not physical phone tests.

## Platform status

All six platform packages were rebuilt. Their archives were checked for integrity, reviewed engine resources and bundled dependency hashes. The Android APK was signed with the existing release key, checked for 16 KiB alignment and verified to request no network or external-storage permission. Its application ID is org.abyssal.engine and its version code is 60.

The packages were not played on Windows, macOS, Linux ARM64 or Android for this release. Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. The browser package uses WebGL 2. No physical phone, mobile browser or physical gamepad was tested for this release.
