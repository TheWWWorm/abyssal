# Abyssal 1.21.1 — platform support

A compatible DEEP JAR must be supplied separately. Original game assets and data are not included.

## Validation

All 42 Python checks and 25 of 26 Godot suites passed on Linux x86-64, both with the default renderer and in compatibility mode. The ocean atmosphere suite reports the existing cabin-light limits also present in 1.21.0; its errors are not new to this release. Engine UI checks cover the station's Load game list, catch notices naming goods and tonnes, and automatic fire resuming after a radio message. Touch input checks cover a swipe past the end of a nested list scrolling the page around it. Graphics settings checks cover the renderer choice: its trial, the return to Vulkan after a failed or interrupted trial, and the row appearing only in the Windows build with AMD's integration. Ocean atmosphere checks cover the Water colour setting from plain water to full region colour. All 1,138 engine texts and 14 translation catalogs passed consistency checks.

The Windows package's engine was checked with Wine, VKD3D-Proton and an NVIDIA GeForce RTX 3090. Without a renderer choice it starts on Vulkan and loads none of AMD's runtime. After Direct3D 12 is chosen, the next start runs Direct3D 12 and loads AMD's runtime with no launcher or command-line options. AMD FSR 3.1 (runtime 3.1.5) upscaled every frame at 100%, 67%, 58% and 50% of the display resolution, and a 33% setting drew at 50% as intended. FSR frame generation (runtime 3.1.6) generated a frame for every drawn frame in flight. A simulated crash during the first Direct3D 12 start returned the next start to Vulkan with the title's notice. FSR 4 and its frame generation need AMD hardware and were not exercised.

The packaged Linux x86-64 executable passed startup, About and shipped-pack checks. The Android APK passed verification against the existing release certificate and 16 KiB alignment checks. Its package is org.abyssal.engine, version 1.21.1, version code 73. It requests no network or broad storage permissions. Inventory and SHA-256 checks cover all six platform packages and the source archive.

## Platform status

Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. On Windows, the Direct3D 12 renderer with AMD FSR needs the Microsoft Visual C++ x64 runtime; it was tested under Wine, not on native Windows or AMD graphics cards. Native Windows, macOS and Linux ARM64 gameplay was not exercised for this release. Mobile browsers and physical gamepads were not tested. Browser play requires WebGL 2. Discord integration is available only in desktop builds and requires the Discord desktop app with activity sharing enabled. Source checks do not establish device performance.
