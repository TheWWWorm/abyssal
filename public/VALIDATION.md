# Abyssal 1.21.17 — platform support

Supply a compatible DEEP JAR separately. Original game assets and texture packs are not included in the downloads; reconstructed textures are generated on the device from the imported atlases.

## Executed checks

All 47 Python regression tests pass. The source regression suite passes all 33 checks headless, including a new check that a ship turns round for a target straight behind it. Headless simulations of the Protect fishes contract (four hunters, a school of eight) finished in all eight seeded runs under each of three player strategies; with the previous code no hunter woke in any of five runs. The chapter 19 school sets out from its own mark and wakes all three hunters. A launch probe on Forward+ moved every shader compilation of the dive's first frames behind the opaque loading screen; the worst visible frame afterwards was 16 ms, against 218 ms before.

The packaged Linux x86-64 executable starts successfully under both Vulkan and OpenGL. On each renderer, the exported game pack passes version and UI checks, enlarged-texture sampling checks, live preview antialiasing checks and normal-map upload UI checks.

The compiled Web build starts, imports a supplied compatible JAR, offers texture reconstruction, and reaches a new-game scene after **Not now** in Linux WebKit. All 544 observed shader compilations and 272 links succeed; no script errors, page errors or failed requests occur.

All six platforms are exported from the same source inventory. Package inspection checks the nested game packs and source archive for private assets.

The Android APK passes signature and 16 KiB alignment verification, retains the existing release certificate, identifies itself as `org.abyssal.engine` version 1.21.17 with version code 89, and requests no network or broad storage permission. Release archive sizes and SHA-256 checksums are verified before publication.

## Platform limits

Windows, macOS and Linux ARM64 native execution is not repeated for this release. Windows and macOS packages are unsigned; macOS is not notarized. Direct3D 12 with AMD FSR requires the Microsoft Visual C++ x64 runtime. No Android device, physical iPhone or iPad, or macOS Safari execution is performed. Browser play requires WebGL 2 and HTTPS or localhost; Linux WebKit checks do not establish Apple-device performance. Texture reconstruction takes longer in a browser than in the desktop build.

The Protect fishes changes are checked by simulation, not by playing the mission. Shader compilations caused later by things first seen in flight are not covered by the launch screen. Intermittent white flashes while firing remain unresolved. Windows Direct3D 12, upscaling and frame generation are not exercised by these checks.
