# Platform support — Abyssal 1.25.0

All six packages contain the engine and local import tools. Original game content is imported from a compatible DEEP JAR supplied by the player.

## Executed checks

The packaged Linux x86-64 executable starts on Vulkan and OpenGL. Fourteen graphical checks pass across the two renderers, covering startup, version and settings, torpedo geometry and opacity, weapon effects, trip tallies, fishing feedback and demo equipment controls. Each renderer passes 49 torpedo checks, 498 combat-feedback checks, 148 tally checks, 85 fishing-feedback checks and 87 demo-interface checks. The tally checks cover passive-radar gating, original icon colours, medal overrides, wrapping and resets.

All 46 engine regression suites complete against the exported Linux game resources with no failed assertions. Forty-five finish without errors in headless mode. The demo-interface suite passes all 87 assertions but reports a dummy-renderer material diagnostic during shutdown; its separate Vulkan and OpenGL runs pass without that error. The suites cover saves, missions, travel, encounters, input, projectile origins, audio, localization and reference content. The 52 Python tooling tests, nine browser viewport tests, seven browser file-picker tests and browser MIDI/music checks pass. Translation validation reports no problems in 1,270 engine texts and 14 catalogs. Six Discord helper tests pass; the optional live-process integration test is skipped.

The compiled Web build starts in Linux WebKit, imports a supplied compatible JAR and reaches a new game. The session reports no script, page or shader-compilation errors, and no failed network requests. Hosted asset checks verify the content-addressed game pack, WebAssembly chunks and static fallback against the tested export.

The Android APK passes signature and 16 KiB alignment verification, retains the existing release certificate, and identifies itself as `org.abyssal.engine` version 1.25.0 with version code 95. It requests no network or broad storage permission.

All six exports use the same game and importer source. Archive inspection checks nested game packs and the source ZIP for private assets. The eight NVIDIA DLLs in the Windows package match the verified official Streamline SDK byte for byte. The local RTX 30-series frame-generation modification is excluded. SHA-256 checksums accompany the downloads.

## Limitations

Windows, macOS, Linux ARM64 and Android device execution is not repeated for this release. Windows Direct3D 12, vendor upscaling and frame generation are not exercised in these tests. Windows and macOS packages are unsigned, and macOS is not notarized. Direct3D 12 with AMD FSR or NVIDIA DLSS requires the Microsoft Visual C++ x64 runtime.

No physical iPhone, iPad or macOS Safari execution is performed. Browser play requires WebGL 2 and HTTPS or localhost; phone-layout and Linux WebKit checks do not establish Apple-device performance. HDR output and performance on integrated or low-memory GPUs are not checked.

The WebKit session emits the same framebuffer-blit diagnostic seen in 1.24.0, while rendering the imported game and passing the shader checks. The graphical demo test reports two ObjectDB instances remaining at process exit. These diagnostics are recorded separately from assertion results; this release does not claim that every graphical regression suite or platform has been exercised.
