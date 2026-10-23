# Abyssal 1.21.15 — platform support

Supply a compatible DEEP JAR separately. Original game assets and texture packs are not included in the downloads.

## Executed checks

All 47 Python regression tests and all 14 translation catalogs pass. The source regression suite passes all 31 checks headless, including the trade screen and the colonist payment shown as a radio message. Golden water keeps a gold hue in the ocean atmosphere check. The golden alga was compared in enhanced renders before and after the change: its measured hue moved from lime (about 83°) to yellow (about 70°), with no shader errors on Vulkan.

The packaged Linux x86-64 executable starts successfully under both Vulkan and OpenGL. On each renderer, the exported game pack passes version and UI checks, enlarged-texture sampling checks, live preview antialiasing checks and normal-map upload UI checks.

The compiled Web build starts, imports a supplied compatible JAR and reaches a new-game scene in Linux WebKit. All 586 observed shader compilations and 293 links succeed; no script errors, page errors or failed requests occur.

Both Linux content packs pass packaged version, UI and normal-loader checks. Their unchanged portable runtimes require no glibc symbols newer than 2.28. All six platforms are exported from the same source inventory. Package inspection checks the nested game packs and source archive for private assets.

The Android APK passes signature and 16 KiB alignment verification, retains the existing release certificate, identifies itself as `org.abyssal.engine` version 1.21.15 with version code 87, and requests no network or broad storage permission. Release archive sizes and SHA-256 checksums are verified before publication.

## Platform limits

Windows, macOS and Linux ARM64 native execution is not repeated for this release. Windows and macOS packages are unsigned; macOS is not notarized. Direct3D 12 with AMD FSR requires the Microsoft Visual C++ x64 runtime. No Android device, physical iPhone or iPad, or macOS Safari execution is performed. Browser play requires WebGL 2 and HTTPS or localhost; Linux WebKit checks do not establish Apple-device performance.

Intermittent white flashes while firing remain unresolved. Windows Direct3D 12, upscaling and frame generation are not exercised by these checks.
