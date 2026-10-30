# Platform support — Abyssal 1.29.0

All seven packages contain the engine and local import tools. Original game content is imported from a compatible DEEP JAR supplied by the player.

## Executed checks

The packaged Linux x86-64 executable starts on Vulkan and OpenGL. On both renderers, the exported game resources pass the translated-settings regression across 15 languages, desktop and touch fonts, and four window sizes: 120 combinations per renderer. Additional rendered checks cover the empty title, Russian settings at 1280×720, 900×1600 and 2400×1080, and starting a new game from a Russian JAR and flying in open water. Captures from both renderers are inspected. Vulkan includes FSR 2.2 at 33% resolution.

All 46 engine regression checks pass against the exported Linux game resources. All 68 Python tests pass, including the Nokia model conversion, class matching across obfuscations and the enlargement of the low-detail build's undersized creatures. The translation check reports no missing or invalid entries across 14 translated catalogs.

The Linux package's bundled offline importer converts three JARs into valid content packs, each with 1,049 strings and 48 campaign chapters: the Russian Sony Ericsson DEEP 1.0.3 JAR, the English Nokia 1.0.8 JAR and the English Nokia 1.0.3 low-detail JAR. Before this release, an import of all eight locally available Nokia JARs (1.0.2, 1.0.3 low detail and 1.0.8, English and Russian) completed. The compiled Web build starts in Linux WebKit 26.5. It imports the Russian Sony Ericsson JAR through its file picker and displays the imported title. In a second run it imports the Nokia low-detail JAR, starts a new game and shows the first tutorial dialogue in open water. No script, page, shader-compilation or network-request errors are observed in either run. Hosted asset checks verify the content-addressed game pack, WebAssembly chunks and static fallback against this export.

The Windows on ARM package contains native ARM64 executables for the game and its offline importer, built from Godot's official 4.7 ARM64 template. It contains no AMD, Microsoft Agility or NVIDIA runtime.

The Android APK passes signature and 16 KiB alignment verification and retains the existing release certificate. It identifies itself as `org.abyssal.engine` version 1.29.0 with version code 101, and requests no network or broad storage permission.

All seven exported importer source archives match the current source. Archive inspection checks nested game packs and the source ZIP for private assets. The eight NVIDIA DLLs in the Windows x86-64 package match the checksum-verified official Streamline SDK byte for byte. The local RTX 30-series frame-generation modification is excluded. SHA-256 checksums accompany the downloads.

## Limitations

Windows (x86-64 and ARM), macOS, Linux ARM64 and Android device execution is not repeated for this release; the Windows on ARM package has never been run on ARM hardware. Windows Direct3D 12, vendor upscaling and frame generation are not exercised in these tests. Windows and macOS packages are unsigned, and macOS is not notarized. Direct3D 12 with AMD FSR or NVIDIA DLSS requires the Microsoft Visual C++ x64 runtime and is available in the x86-64 Windows package only.

Nokia content is checked through import, the title, the start of a new game and early flight. A full campaign with a Nokia JAR has not been played. Nokia builds keep the visual differences of their own models, as described in the README.

No physical iPhone, iPad or macOS Safari execution is performed. Browser play requires WebGL 2 and HTTPS or localhost. Phone-layout and Linux WebKit checks do not establish Apple-device performance. HDR output and performance on integrated or low-memory GPUs are not checked.
