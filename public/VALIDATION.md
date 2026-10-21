# Abyssal 1.21.6 — platform support

A compatible DEEP JAR must be supplied separately. Original game assets and data are not included.

## Validation

All 45 Python checks and all 26 Godot suites passed on Linux x86-64, both in default and OpenGL compatibility mode. These include the Standard and Classic controller layouts, migration of customized controls, Trade and Workshop navigation, story arrival exchanges, station shadows, and graphics presets preserving independent antialiasing choices. All 1,153 engine texts and 14 translation catalogs passed consistency checks. Importer, browser audio and Discord IPC checks also passed.

The packaged Linux x86-64 game passed rendered Vulkan and OpenGL startup checks and a shipped-content check of the title, settings, controller layout, compact depth warning, map labels and About page. The Windows package started on Vulkan, OpenGL and Direct3D 12 with AMD's FidelityFX runtime under Wine and VKD3D-Proton on an NVIDIA GeForce RTX 3090. Chromium launched the exported WebGL 2 build at 1920 × 1080, with the versioned JavaScript and WebAssembly runtime.

Rendered shadow-cache checks passed on Linux, Windows under Wine, Chromium WebGL, and the Retroid Pocket 5 with Vulkan and OpenGL ES. Cached shadows matched freshly rendered shadows after caster and light movement, visibility and layer changes, atlas resizing and LOD changes. The synthetic OpenGL lighting check reduced draw calls from 28 to 12 with matching rendered colours. The RP5 check used a separate test application.

The Android APK passed verification against the existing release certificate and 16 KiB alignment checks. Its package is org.abyssal.engine, version 1.21.6, version code 78. It requests no network or broad storage permissions. All six platform packages and the source archive are checked for inventory, private-content exclusion and SHA-256 integrity.

## Performance and runtime coverage

The custom Godot runtime contains station shadow caching and lighting optimizations in the Windows, Linux x86-64, Linux ARM64, Android ARM64 and Web packages. macOS and Android x86-64 retain their existing runtimes and receive the shared game-side station shader and shadow-geometry improvements. Antialiasing remains independent of graphics presets; native-resolution rendering does not require upscaling.

In controlled native 1920 × 1080, Very high, AA-off Gosu close-up checks on a Linux desktop with an RTX 3090, the patched runtime improved the sampled Vulkan result from about 122 to 171 FPS and OpenGL from about 124 to 141 FPS. Those comparisons used the same local compiler settings for both runtimes; they are not measurements of every packaged platform. Browser results varied between runs and stations. A locked 60 FPS at native 1080p has not been established on every device or station.

## Platform limits

The Linux x86-64 and ARM64 executables were built with Godot’s portable Buildroot SDK and require no glibc symbols newer than 2.28. The final x86-64 binaries passed Vulkan and OpenGL startup and rendered shadow-cache checks.

Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. Direct3D 12 with AMD FSR requires the Microsoft Visual C++ x64 runtime. Native Windows, macOS and Linux ARM64 gameplay was not exercised for this release. Physical controller navigation and fresh JAR import were not retested on every target device. Mobile browsers were not tested. Browser play requires WebGL 2. Discord integration requires the Discord desktop app and activity sharing. Source checks and cross-compilation do not establish device performance.
