# Abyssal Engine 1.17.4 — Web support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

All 42 Python unit tests passed on Linux x86-64. The headless Godot UI, platform input (340 assertions), controller UI (67 assertions) and localization checks passed. All 906 engine texts and 14 translation catalogs passed their consistency and font-coverage checks.

UI checks cover simultaneous fading notices and duplicate messages, wrapped notices in portrait layouts, rereading radio dialogue without repeating completion, the saved pilot portrait, optional wheel throttle and both S-key modes. With wheel throttle off, S retains graduated throttle-down input and gradual deceleration. With it on, S immediately stops forward motion, including during boost and autopilot; held and rebound keys were checked.

The interface was rendered on Linux with OpenGL Compatibility at 1280×720 and 589×1280. The notice stack, wrapped messages, dialogue Back button, pilot profile and steering settings were checked at those sizes. These are viewport checks, not physical phone tests.

The Godot 4.7 release Web export was opened locally in Chromium at 1280×720. The title rendered with version 1.17.4, wheel throttle began disabled, and enabling and disabling it changed the S binding between Stop and Throttle down. No browser warnings or errors were reported during that check.

The exported game pack contains only allowlisted engine resources. The bundled importer dependencies match their pinned checksums. Hosting assets are checked against the 25 MiB limit, with the engine WebAssembly split into parts that reconstruct the original file. Previous content-hashed game packs remain available for pages opened before the update.

## Platform status

This update prepares the hosted WebGL 2 build. Native packages and their platform validation are available on the [releases page](https://github.com/TheWWWorm/abyssal/releases). Physical phones, mobile browsers and physical gamepads were not exercised for this build.
