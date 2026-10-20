# Abyssal 1.21.2 — platform support

A compatible DEEP JAR must be supplied separately. Original game assets and data are not included.

## Validation

All 42 Python checks and 25 of 26 Godot suites passed on Linux x86-64, both with the default renderer and in compatibility mode. The ocean atmosphere suite reports the existing cabin-light limits also present in 1.21.1; its errors are not new to this release. Graphics settings checks cover the renderer choice: the Vulkan and OpenGL choices, the trial, the return to Vulkan after a failed or interrupted trial with the renderer named, a Direct3D 12 choice kept from 1.21.1, and the Renderer row's value fitting beside its name. All 1,140 engine texts and 14 translation catalogs passed consistency checks.

The renderer choice was checked on three platforms. On Linux x86-64 with an NVIDIA GeForce RTX 3090, the exported game starts on Vulkan; after OpenGL is chosen, the next start runs OpenGL and keeps it, and an interrupted trial returns to Vulkan. On Android, a Retroid Pocket 5 (Adreno 650) started on OpenGL ES 3.2 after OpenGL was chosen in Settings and drew the title correctly; closing the app during the first minute returned the next start to Vulkan with the title's notice.

The Windows package was checked with Wine, VKD3D-Proton and the same RTX 3090. Without a renderer choice it starts on Vulkan and loads none of AMD's runtime. After OpenGL is chosen the next start runs OpenGL; after Direct3D 12 is chosen it runs Direct3D 12 and loads AMD's FidelityFX runtime. A Direct3D 12 choice saved by 1.21.1 still starts Direct3D 12. FSR 4 and its frame generation need AMD hardware and were not exercised.

The packaged Linux x86-64 executable passed startup, About, Renderer row and shipped-pack checks. The Android APK passed verification against the existing release certificate and 16 KiB alignment checks. Its package is org.abyssal.engine, version 1.21.2, version code 74. It requests no network or broad storage permissions. Inventory and SHA-256 checks cover all six platform packages and the source archive.

## Platform status

Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. On Windows, the Direct3D 12 renderer with AMD FSR needs the Microsoft Visual C++ x64 runtime; it was tested under Wine, not on native Windows or AMD graphics cards. Native Windows, macOS and Linux ARM64 gameplay was not exercised for this release. Mobile browsers and physical gamepads were not tested. Browser play requires WebGL 2. Discord integration is available only in desktop builds and requires the Discord desktop app with activity sharing enabled. Source checks do not establish device performance.
