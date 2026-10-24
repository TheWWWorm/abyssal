# Abyssal 1.21.16 — platform support

Supply a compatible DEEP JAR separately. Original game assets and texture packs are not included in the downloads; reconstructed textures are generated on the device from the imported atlases.

## Executed checks

All 47 Python regression tests and all 14 translation catalogs pass. The source regression suite passes all 33 checks headless, including texture reconstruction (generation, cache reuse, cancellation and the import and first-launch offer), autopilot turning, station contact, chained radio messages and full-hold salvage. A headless flight comparison of 64 docking approaches measured steadier autopilot turns: the largest tick-to-tick change in turn rate fell from 0.56 to 0.17 rad/s, the hull no longer tilts while turning, and the flown paths are slightly shorter.

The packaged Linux x86-64 executable starts successfully under both Vulkan and OpenGL. On each renderer, the exported game pack passes version and UI checks, enlarged-texture sampling checks, live preview antialiasing checks and normal-map upload UI checks.

The compiled Web build starts, imports a supplied compatible JAR, offers texture reconstruction, and reaches a new-game scene after **Not now** in Linux WebKit. All 552 observed shader compilations and 276 links succeed; no script errors, page errors or failed requests occur.

All six platforms are exported from the same source inventory. Package inspection checks the nested game packs and source archive for private assets.

The Android APK passes signature and 16 KiB alignment verification, retains the existing release certificate, identifies itself as `org.abyssal.engine` version 1.21.16 with version code 88, and requests no network or broad storage permission. Release archive sizes and SHA-256 checksums are verified before publication.

## Platform limits

Windows, macOS and Linux ARM64 native execution is not repeated for this release. Windows and macOS packages are unsigned; macOS is not notarized. Direct3D 12 with AMD FSR requires the Microsoft Visual C++ x64 runtime. No Android device, physical iPhone or iPad, or macOS Safari execution is performed. Browser play requires WebGL 2 and HTTPS or localhost; Linux WebKit checks do not establish Apple-device performance. Texture reconstruction takes longer in a browser than in the desktop build.

Intermittent white flashes while firing remain unresolved. Windows Direct3D 12, upscaling and frame generation are not exercised by these checks.
