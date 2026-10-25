# Platform support — Abyssal 1.22.0

All six packages contain the engine and local import tools. Original game content is imported from a compatible DEEP JAR supplied by the player.

## Executed checks

The packaged Linux x86-64 executable starts on Vulkan and OpenGL. Its exported game resources pass version, title and settings checks on both renderers. Classic sky and distant-surface fog match at 3840×2160 on both, with a compact white sun core and dark lower water. The full ocean-atmosphere regression passes on Vulkan. The UI and menu checks pass on OpenGL, including the Retro HUD default, saved preferences, objective travel choices, menu wrapping and browsing the mission board during an active contract.

The compiled Web build starts in Linux WebKit, imports a supplied compatible JAR, offers texture reconstruction and reaches a new game after choosing **Not now**. The checked session reports no script, page or shader-compilation errors, and no failed network requests.

Source checks cover ship contact, navigation, travel, mission targets, controls and menu behavior. The Python tooling suite passes 47 tests; all 1,241 engine texts are present in the 14 non-English catalogs.

The Android APK passes signature and 16 KiB alignment verification, retains the existing release certificate, and identifies itself as `org.abyssal.engine` version 1.22.0 with version code 92. It requests no network or broad storage permission.

All packages are exported from one unchanged source inventory. Archive inspection checks nested game packs and the source ZIP for private assets. The eight NVIDIA DLLs in the Windows package match the checksum-verified official Streamline SDK byte for byte. The local RTX 30-series frame-generation modification is excluded. SHA-256 checksums accompany the downloads.

## Limitations

Windows, macOS, Linux ARM64 and Android device execution is not repeated for this release. Windows Direct3D 12, vendor upscaling and frame generation are not exercised in this release's tests. Windows and macOS packages are unsigned, and macOS is not notarized. Direct3D 12 with AMD FSR or NVIDIA DLSS requires the Microsoft Visual C++ x64 runtime.

No physical iPhone, iPad or macOS Safari execution is performed. Browser play requires WebGL 2 and HTTPS or localhost; Linux WebKit checks do not establish Apple-device performance. HDR output and performance on integrated or low-memory GPUs are not checked.

OpenGL UI assertions pass, but the renderer reports texture-cleanup diagnostics at process shutdown. This release does not claim a pass for every graphical regression suite.
