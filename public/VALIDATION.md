# Platform support — Abyssal 1.25.1

All six packages contain the engine and local import tools. Original game content is imported from a compatible DEEP JAR supplied by the player.

## Executed checks

The packaged Linux x86-64 executable starts on Vulkan and OpenGL and identifies itself as version 1.25.1. Each renderer passes three graphical checks covering startup, packaged version and settings, and the mission-completion currency display. The completion dialogue uses the imported gold coin in all 15 engine languages. Imported story amounts and engine-authored amounts display their symbols together. Desktop, portrait-phone and landscape-phone layouts are checked, with English, Russian and Japanese captures inspected.

Three engine regression suites pass against the exported Linux resources: session and reward state, open-world mission progression, and engine-language handling. This patch changes only the dialogue's currency formatting. Broader 1.25.0 checks are documented in that release's validation record and are not counted as newly executed checks here.

The compiled Web build starts in Linux WebKit, imports a supplied compatible JAR and reaches a new game. The session reports no script, page or shader-compilation errors, and no failed network requests. Hosted asset checks verify the content-addressed game pack, WebAssembly chunks and static fallback against the tested export.

The Android APK passes signature and 16 KiB alignment verification, retains the existing release certificate, and identifies itself as `org.abyssal.engine` version 1.25.1 with version code 96. It requests no network or broad storage permission.

All six exports use the same game and importer source. Archive inspection checks nested game packs and the source ZIP for private assets. The eight NVIDIA DLLs in the Windows package match the verified official Streamline SDK byte for byte. The local RTX 30-series frame-generation modification is excluded. SHA-256 checksums accompany the downloads.

## Limitations

Windows, macOS, Linux ARM64 and Android device execution is not repeated for this release. Windows Direct3D 12, vendor upscaling and frame generation are not exercised in these tests. Windows and macOS packages are unsigned, and macOS is not notarized. Direct3D 12 with AMD FSR or NVIDIA DLSS requires the Microsoft Visual C++ x64 runtime.

No physical iPhone, iPad or macOS Safari execution is performed. Browser play requires WebGL 2 and HTTPS or localhost; phone-layout and Linux WebKit checks do not establish Apple-device performance. HDR output and performance on integrated or low-memory GPUs are not checked. The WebKit session emits the framebuffer-blit diagnostic already observed in 1.25.0 while rendering the game and passing the shader checks.
