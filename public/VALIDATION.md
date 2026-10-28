# Platform support — Abyssal 1.27.0

All six packages contain the engine and local import tools. Original game content is imported from a compatible DEEP JAR supplied by the player.

## Executed checks

The packaged Linux x86-64 executable starts on Vulkan and OpenGL and identifies itself as version 1.27.0. Each renderer passes three graphical checks: startup, packaged version and settings, and this release's changes. The last check runs on a 2400×1080 touch screen in Russian. It confirms that the chart's actions keep to one row at a 100%, 90% and 80% interface. A rebel shipyard shows its upgraded hulls in the rebel livery. Every module of the starting station is drawn a fraction smaller, with its separating move kept. Enhanced station modules carry their distant glow. The new shaders are packaged, the unused seabed is not, motion cues start on and calibrated materials start off. Captures from both renderers are inspected.

Three engine regression suites pass against the exported Linux resources: the engine interface (including the chart's action row), station streaming (including the 2 cm clearance between overlapping module faces at the current, streamed and moved stations) and the ocean options. The full source regression suite of 45 checks also passes. Broader checks from earlier releases are documented in their own validation records and are not counted as newly executed checks here.

The compiled Web build starts in Linux WebKit, imports a supplied compatible JAR and reaches a new game. The session reports no script, page or shader-compilation errors, and no failed network requests. Hosted asset checks verify the content-addressed game pack, WebAssembly chunks and static fallback against the tested export.

The Android APK passes signature and 16 KiB alignment verification and keeps the existing release certificate. It identifies itself as `org.abyssal.engine` version 1.27.0 with version code 98, and requests no network or broad storage permission.

All six exports use the same game and importer source. Archive inspection checks nested game packs and the source ZIP for private assets. The eight NVIDIA DLLs in the Windows package match the verified official Streamline SDK byte for byte. The local RTX 30-series frame-generation modification is excluded. SHA-256 checksums accompany the downloads.

## Limitations

Windows, macOS, Linux ARM64 and Android device execution is not repeated for this release. Windows Direct3D 12, vendor upscaling and frame generation are not exercised in these tests. Screen-space reflections from calibrated materials and the water refraction behind detonations are not separately captured. Windows and macOS packages are unsigned, and macOS is not notarized. Direct3D 12 with AMD FSR or NVIDIA DLSS requires the Microsoft Visual C++ x64 runtime.

No physical iPhone, iPad or macOS Safari execution is performed. Browser play requires WebGL 2 and HTTPS or localhost. Phone-layout and Linux WebKit checks do not establish Apple-device performance. HDR output and performance on integrated or low-memory GPUs are not checked.
