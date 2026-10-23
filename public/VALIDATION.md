# Abyssal 1.21.13 — platform support

Supply a compatible DEEP JAR separately. Original game assets, data and texture packs are not included in the downloads.

## Normal maps

Normal-map loading, reload, removal, Restore original and model deformation checks pass. Ten rendered checks pass under OpenGL and ten under Vulkan Forward+. These cover normal orientation, mirrored UVs, animated parts, degenerate UVs, the original atlas coordinate scale and transparent normal-map boundaries. Without a normal map, and after removal or Restore original, the captured result matches the previous material byte for byte.

All 46 Python regression tests pass. The public source inventory is checked against the source allowlist. Release archives, nested game packs and the Android APK are inspected to exclude original content and private texture packs.

The compiled Web build starts, imports a supplied compatible JAR and reaches a new-game scene in Linux WebKit. Instrumentation records 600 successful shader compiles and 300 successful links, including the normal-map material path, with no script or page errors. A texture pack was not installed in the browser. WebKit reports framebuffer validation messages also present in 1.21.12; these are retained as a platform limitation.

## Packages

All six platform packages are exported from the same source. The compiled Linux x86-64 executable passes rendered Vulkan and OpenGL startup. Both Linux content packs pass packaged version, UI and normal-map loader/shader checks. Linux x86-64 and ARM64 retain the portable runtimes used since 1.21.6 and require no glibc symbols newer than 2.28. The station-rendering engines and Windows AMD FidelityFX runtime are unchanged.

The Android APK passes signature and 16 KiB alignment verification, uses the existing release certificate, identifies itself as org.abyssal.engine version 1.21.13, version code 85, and requests no network or broad storage permission. Package contents, source inventory and SHA-256 checksums are verified before publication.

## Platform limits

Windows, macOS and Linux ARM64 runtime execution was not rerun for this release. Windows and macOS packages are unsigned; macOS is not notarized. Direct3D 12 with AMD FSR requires the Microsoft Visual C++ x64 runtime. This release was not run on an Android device, physical iPhone or iPad, or macOS Safari. Browser play requires WebGL 2 and an HTTPS host or localhost. Linux browser checks do not establish Apple-device performance.

Intermittent white flashes while firing remain unresolved. Windows Direct3D 12, upscaling and frame generation were not exercised for this report.
