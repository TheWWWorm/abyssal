# Abyssal 1.21.0 — platform support

A compatible DEEP JAR must be supplied separately. Original game assets and data are not included.

## Validation

All 42 Python checks and 25 of 26 Godot suites passed on Linux x86-64, both with the default renderer and in compatibility mode. The ocean atmosphere suite reports the existing cabin-light limits also present in 1.20.2; its errors are not new to this release. Engine UI checks cover **About**: both tabs, the original game's copyright and credits, and the remake's four links. Gamepad menu checks cover reaching About from the main menu, its tabs and returning to the menu. Graphics settings checks cover the FSR 3.1 and FSR 4 choices falling back where AMD's runtime is absent. All 1,129 engine texts and 14 translation catalogs passed consistency checks.

The Windows FSR engine build was checked with Wine, VKD3D-Proton and an NVIDIA GeForce RTX 3090 on Direct3D 12. AMD FSR 3.1 (runtime 3.1.5) upscaled every frame at 100%, 67%, 58% and 50% of the display resolution, and a 33% setting drew at 50% as intended. FSR frame generation (runtime 3.1.6) generated a frame for every drawn frame in flight. FSR 4 and its frame generation need AMD hardware and were not exercised. The exported FSR package was started the way its `Play-FSR.cmd` starts it and loaded AMD's runtime.

The packaged Linux x86-64 executable passed startup, About and shipped-pack checks. The Android APK passed verification against the existing release certificate and 16 KiB alignment checks. Its package is org.abyssal.engine, version 1.21.0, version code 72. It requests no network or broad storage permissions. Inventory and SHA-256 checks cover all seven platform packages and the source archive.

## Platform status

Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. The Windows FSR package needs Direct3D 12 and the Microsoft Visual C++ x64 runtime; it was tested under Wine, not on native Windows or AMD graphics cards. Native Windows, macOS and Linux ARM64 gameplay was not exercised for this release. Mobile browsers and physical gamepads were not tested. Browser play requires WebGL 2. Discord integration is available only in desktop builds and requires the Discord desktop app with activity sharing enabled. Source checks do not establish device performance.
