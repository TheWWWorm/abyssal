# Abyssal 1.21.5 — platform support

A compatible DEEP JAR must be supplied separately. Original game assets and data are not included.

## Validation

All 42 Python checks and all 26 Godot suites passed on Linux x86-64, both with the default renderer and in compatibility mode. Interface checks cover the time left shown for a timed job, the dock key asking before docking, autopilot docking at the station's berth, and the travel question on the chart, on Initiate transit and again at the gate. Readability checks cover the drifting particles keeping their phase when the region origin moves. All 1,147 engine texts and 14 translation catalogs passed consistency checks.

The packaged Linux x86-64 executable passed startup, About, Renderer row, map label and shipped-pack checks, and its renderer choice was checked with Vulkan by default, OpenGL after a choice, and a return to Vulkan after an interrupted trial on an NVIDIA GeForce RTX 3090. The Windows package was checked with Wine, VKD3D-Proton and the same card: it starts on Vulkan, runs OpenGL or Direct3D 12 with AMD's FidelityFX runtime after the matching choice, and keeps a Direct3D 12 choice saved by 1.21.1. The Android APK passed verification against the existing release certificate and 16 KiB alignment checks. Its package is org.abyssal.engine, version 1.21.5, version code 77. It requests no network or broad storage permissions. Inventory and SHA-256 checks cover all six platform packages and the source archive.

## Platform status

Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. On Windows, the Direct3D 12 renderer with AMD FSR needs the Microsoft Visual C++ x64 runtime; it was tested under Wine, not on native Windows or AMD graphics cards. Native Windows, macOS and Linux ARM64 gameplay was not exercised for this release. Android devices, mobile browsers and physical gamepads were not tested for this release. Browser play requires WebGL 2. Discord integration is available only in desktop builds and requires the Discord desktop app with activity sharing enabled. Source checks do not establish device performance.
