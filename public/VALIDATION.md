# Abyssal 1.21.18 — platform support

Supply a compatible DEEP JAR separately. Original game assets and texture packs are not included in the downloads; reconstructed textures are generated on the device from the imported atlases.

## Executed checks

All 47 Python regression tests pass. The source regression suite passes all 33 checks headless, including the renderer choices: Direct3D 12 with AMD FSR loads only AMD's runtime and Direct3D 12 with NVIDIA DLSS only NVIDIA's.

The Windows package's engine and game pack were run through Proton 11 (VKD3D-Proton and DXVK-NVAPI) on an NVIDIA RTX 3090 and RTX 3090 Ti with driver 580.178.04. Chosen in Settings, **Direct3D 12 · NVIDIA DLSS** starts on Direct3D 12, loads NVIDIA's signed runtime and no AMD library, and shows the NVIDIA DLSS splash and credits. Through the settings screen, DLSS upscaled every one of 120 frames at DLAA, Quality, Balanced, Performance and below-half settings, with no runtime error. On these RTX 30-series cards NVIDIA's runtime reports frame generation as unsupported, and the setting is shown as unavailable. **Direct3D 12 · AMD FSR** still upscales with FSR 3.1 at every setting and generated 180 frames in flight.

The packaged Linux x86-64 executable starts successfully under both Vulkan and OpenGL. On each renderer, the exported game pack passes version and UI checks, enlarged-texture sampling checks, live preview antialiasing checks and normal-map upload UI checks.

The compiled Web build starts, imports a supplied compatible JAR, offers texture reconstruction, and reaches a new-game scene after **Not now** in Linux WebKit, with no script errors, page errors or failed requests.

All six platforms are exported from the same source inventory. Package inspection checks the nested game packs and source archive for private assets.

The Android APK passes signature and 16 KiB alignment verification, retains the existing release certificate, identifies itself as `org.abyssal.engine` version 1.21.18 with version code 90, and requests no network or broad storage permission. Release archive sizes and SHA-256 checksums are verified before publication.

## Platform limits

Windows, macOS and Linux ARM64 native execution is not repeated for this release; the Direct3D 12 checks above ran through Proton, not on Windows itself. DLSS Frame Generation on the RTX 40 and 50 series it supports is not exercised: its frame pacing, Reflex latency and interface-edge artefacts are unverified. HDR output is not checked. Windows and macOS packages are unsigned; macOS is not notarized. Direct3D 12 with AMD FSR or NVIDIA DLSS requires the Microsoft Visual C++ x64 runtime. No Android device, physical iPhone or iPad, or macOS Safari execution is performed. Browser play requires WebGL 2 and HTTPS or localhost; Linux WebKit checks do not establish Apple-device performance. Texture reconstruction takes longer in a browser than in the desktop build.
