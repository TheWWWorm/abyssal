# Platform support — Abyssal 1.23.0

All six packages contain the engine and local import tools. Original game content is imported from a compatible DEEP JAR supplied by the player.

## Executed checks

The packaged Linux x86-64 executable starts on Vulkan and OpenGL. Seventeen graphical checks pass across the two renderers, covering version and settings, Classic sky at 3840×2160, weapon effects, catch feedback, demo equipment controls and the independent weapon options. The atmosphere suite also passes on Vulkan, and the menu and UI suites pass on OpenGL. Fresh settings enable both Enhanced weapon effects and Added weapon sounds; switching and saving either option leaves the other independent.

All 44 engine regression suites pass against the exported Linux game resources in headless mode. They cover mission encounters and recovery, travel and routing, cooldown presentation, touch input, projectile origins, recorded audio, the demo's isolation from campaign saves, and reference content. The 52 Python tooling tests and nine browser viewport tests pass. Graphical pixel checks are reported separately from headless checks.

The compiled Web build starts in Linux WebKit, imports a supplied compatible JAR, offers texture reconstruction and reaches a new game after choosing **Not now**. The session reports no script, page or shader-compilation errors, and no failed network requests. Hosted asset checks verify the content-addressed game pack, WebAssembly chunks and static fallback against the tested export.

The Android APK passes signature and 16 KiB alignment verification, retains the existing release certificate, and identifies itself as `org.abyssal.engine` version 1.23.0 with version code 93. It requests no network or broad storage permission.

All six exports use the same game and importer source. Archive inspection checks nested game packs and the source ZIP for private assets. The 48 added weapon recordings match their provenance hashes, with their licences and credits included. The eight NVIDIA DLLs in the Windows package match the verified official Streamline SDK byte for byte. The local RTX 30-series frame-generation modification is excluded. SHA-256 checksums accompany the downloads.

## Limitations

Windows, macOS, Linux ARM64 and Android device execution is not repeated for this release. Windows Direct3D 12, vendor upscaling and frame generation are not exercised in these tests. Windows and macOS packages are unsigned, and macOS is not notarized. Direct3D 12 with AMD FSR or NVIDIA DLSS requires the Microsoft Visual C++ x64 runtime.

No physical iPhone, iPad or macOS Safari execution is performed. Browser play requires WebGL 2 and HTTPS or localhost; the viewport regressions and Linux WebKit checks do not establish Apple-device performance. HDR output and performance on integrated or low-memory GPUs are not checked.

OpenGL UI assertions pass, but the renderer reports texture-cleanup diagnostics at process shutdown. This release does not claim a pass for every graphical regression suite.
