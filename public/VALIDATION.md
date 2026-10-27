# Platform support — Abyssal 1.26.0

All six packages contain the engine and local import tools. Original game content is imported from a compatible DEEP JAR supplied by the player.

## Executed checks

The packaged Linux x86-64 executable starts on Vulkan and OpenGL and identifies itself as version 1.26.0. Each renderer passes three graphical checks: startup, packaged version and settings, and this release's interface changes. On a 2400×1080 touch screen in Russian, the last check confirms several things. An 80% interface uses a larger canvas while the picture still fills the window. The chart's species card keeps its caption on one line. The autopilot chart offers the S.T.R.E.A.M. transfer. **Check location** is centred, and enemy hull bars read to the doubled range. Captures from both renderers are inspected.

Three engine regression suites pass against the exported Linux resources: open-world mission progression (including the contract briefing on arrival), the engine interface (including interface size) and engine-language handling. The full source regression suite of 46 checks also passes. Broader checks from earlier releases are documented in their own validation records and are not counted as newly executed checks here.

The compiled Web build starts in Linux WebKit, imports a supplied compatible JAR and reaches a new game. The session reports no script, page or shader-compilation errors, and no failed network requests. Hosted asset checks verify the content-addressed game pack, WebAssembly chunks and static fallback against the tested export.

The Android APK passes signature and 16 KiB alignment verification and keeps the existing release certificate. It identifies itself as `org.abyssal.engine` version 1.26.0 with version code 97, and requests no network or broad storage permission.

All six exports use the same game and importer source. Archive inspection checks nested game packs and the source ZIP for private assets. The eight NVIDIA DLLs in the Windows package match the verified official Streamline SDK byte for byte. The local RTX 30-series frame-generation modification is excluded. SHA-256 checksums accompany the downloads.

## Limitations

Windows, macOS, Linux ARM64 and Android device execution is not repeated for this release. Windows Direct3D 12, vendor upscaling and frame generation are not exercised in these tests. Windows and macOS packages are unsigned, and macOS is not notarized. Direct3D 12 with AMD FSR or NVIDIA DLSS requires the Microsoft Visual C++ x64 runtime.

No physical iPhone, iPad or macOS Safari execution is performed. Browser play requires WebGL 2 and HTTPS or localhost. Phone-layout and Linux WebKit checks do not establish Apple-device performance. HDR output and performance on integrated or low-memory GPUs are not checked.
