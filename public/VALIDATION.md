# Platform support — Abyssal 1.24.0

All six packages contain the engine and local import tools. Original game content is imported from a compatible DEEP JAR supplied by the player.

## Executed checks

The packaged Linux x86-64 executable starts on Vulkan and OpenGL. Seventeen graphical checks pass across the two renderers, covering version and settings, Classic sky at 3840×2160, weapon effects, fishing feedback, demo equipment controls and independent weapon options. Each renderer passes 497 weapon checks and 85 fishing checks, including the new Mass Driver energy bolts and four fishing feedback modes. The atmosphere suite passes on Vulkan; the menu and UI suites pass on OpenGL.

Two additional OpenGL checks pass against the exported resources. The fishing dropdown passes 300 layout and default-setting checks across all 15 engine languages on portrait and landscape phone layouts. The reconstruction integration check generates textures, reopens the cache, toggles the feature in the title and game, and returns to the main menu while preserving the same loaded content and saved choices, without another file-verification pass or graphics benchmark.

All 44 engine regression suites pass against the exported Linux game resources in headless mode. They cover mission rewards, Eclipse sale rules, ship contact and travel, encounters and recovery, cooldowns, input, projectile origins, weapon audio, demo isolation, localization and reference content. Graphical pixel checks are reported separately. The 52 Python tooling tests, nine browser viewport tests, seven browser file-picker tests and browser MIDI/music checks pass.

The compiled Web build starts in Linux WebKit, imports a supplied compatible JAR and reaches a new game. The session reports no script, page or shader-compilation errors, and no failed network requests. Hosted asset checks verify the content-addressed game pack, WebAssembly chunks and static fallback against the tested export.

The Android APK passes signature and 16 KiB alignment verification, retains the existing release certificate, and identifies itself as `org.abyssal.engine` version 1.24.0 with version code 94. It requests no network or broad storage permission.

All six exports use the same game and importer source. Archive inspection checks nested game packs and the source ZIP for private assets. The 48 added weapon recordings match their provenance hashes, with their licences and credits included. The eight NVIDIA DLLs in the Windows package match the verified official Streamline SDK byte for byte. The local RTX 30-series frame-generation modification is excluded. SHA-256 checksums accompany the downloads.

## Limitations

Windows, macOS, Linux ARM64 and Android device execution is not repeated for this release. Windows Direct3D 12, vendor upscaling and frame generation are not exercised in these tests. Windows and macOS packages are unsigned, and macOS is not notarized. Direct3D 12 with AMD FSR or NVIDIA DLSS requires the Microsoft Visual C++ x64 runtime.

No physical iPhone, iPad or macOS Safari execution is performed. Browser play requires WebGL 2 and HTTPS or localhost; phone-layout and Linux WebKit checks do not establish Apple-device performance. HDR output and performance on integrated or low-memory GPUs are not checked.

OpenGL UI assertions pass, but the renderer reports known texture-cleanup diagnostics at process shutdown. This release does not claim a pass for every graphical regression suite.
