# Abyssal 1.21.14 — platform support

Supply a compatible DEEP JAR separately. Original game assets, texture packs and the base-texture upscaling experiment are not included in the downloads.

## Executed checks

All 47 Python regression tests and all 14 translation catalogs pass. The source regression run completes 31 checks: 29 headless checks pass and two GPU-only checks defer to rendered execution.

The packaged Linux x86-64 executable starts successfully under both Vulkan and OpenGL. On each renderer, the exported game pack passes version and UI checks, enlarged-texture sampling checks, live preview antialiasing checks and normal-map upload UI checks. The texture checks cover minification during camera movement, preservation of individual replacement texels, constant-UV paint samples and restoration after removing a replacement. The normal-map checks cover independent colour/normal slots, immediate reload, preview, removal, failed imports, temporary-file cleanup, three window sizes and seven translated layouts.

Controlled ship and station motion captures use identical cameras, 4× multisampling and no normal maps. Corrected replacement sampling reduces the measured temporal error against a supersampled reference by about 55% inside both models and by 14–25% near their outlines. These are specific comparison scenes, not a guarantee that every kind of aliasing is eliminated. With texture smoothing enabled, finer replacement artwork can still expose more aliasing than the original artwork.

The compiled Web build starts, imports a supplied compatible JAR and reaches a new-game scene in Linux WebKit. All 572 observed shader compilations and 286 links succeed, including the normal-map material path; no script errors, page errors or failed requests occur. A replacement texture pack is not installed in this browser check. WebKit still reports framebuffer validation messages also observed in earlier releases.

Both Linux content packs pass packaged version, UI and normal-loader checks. Their unchanged portable runtimes require no glibc symbols newer than 2.28. All six platforms are exported from the same source inventory. Package inspection checks the nested game packs and source archive for private assets and the excluded enhancement tool.

The Android APK passes signature and 16 KiB alignment verification, retains the existing release certificate, identifies itself as `org.abyssal.engine` version 1.21.14 with version code 86, and requests no network or broad storage permission. Release archive sizes and SHA-256 checksums are verified before publication.

## Platform limits

Windows, macOS and Linux ARM64 native execution is not repeated for this release. Windows and macOS packages are unsigned; macOS is not notarized. Direct3D 12 with AMD FSR requires the Microsoft Visual C++ x64 runtime. No Android device, physical iPhone or iPad, or macOS Safari execution is performed. Browser play requires WebGL 2 and HTTPS or localhost; Linux WebKit checks do not establish Apple-device performance.

Intermittent white flashes while firing remain unresolved. Windows Direct3D 12, upscaling and frame generation are not exercised by these checks.
