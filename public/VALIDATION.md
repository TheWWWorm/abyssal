# Abyssal 1.21.8 — platform support

A compatible DEEP JAR must be supplied separately. Original game assets and data are not included in the downloads.

## Import and startup

The language choice now appears before 3D title preparation. Installation and station construction yield between batches and display progress. The title no longer warms the entire model catalogue. Saved imports are checked before rendering; damaged content returns to the picker without removing expedition saves. Reimport also repairs a damaged cache inventory.

The compiled Web build imported a supplied JAR in Linux WebKit 26.5. Desktop and portrait phone viewport checks covered closing at the English/Russian language choice, reopening and answering it, interrupting installation, and recovering from damaged cached content. Reimport remained available without clearing site data, and a stored save-data sentinel survived recovery. No script or persistence errors occurred in these checks.

A separate instrumented Android test application ran on a Retroid Pocket 5 with the same patched ARM64 engine. A privately prepared localized content pack reached the language choice before scene construction. The choice responded to touch, and force-stopping and reopening retained the import and language selection. This checks installation and startup, not a complete gameplay session or the system file picker.

The 46 Python checks, including seven browser picker lifecycle checks, passed. Native checks passed for content integrity and recovery, startup sequencing, engine UI, controller navigation, graphics settings, world spacing, platform input, and ocean options.

## Packages

All six platform packages were exported from the same source. Linux x86-64 passed rendered Vulkan and OpenGL startup checks and packaged UI and version checks. Linux x86-64 and ARM64 retain the portable 1.21.6 runtimes and require no glibc symbols newer than 2.28.

The Android APK uses the existing release certificate, passes signature and 16 KiB alignment verification, and identifies itself as org.abyssal.engine version 1.21.8, version code 80. It requests no network or broad storage permission. Package contents, the source archive and SHA-256 checksums are verified before publication.

The station-rendering runtimes and Windows AMD FidelityFX runtime are unchanged from 1.21.6.

## Platform limits

Physical iPhone, iPad and macOS Safari were not tested. Linux WebKit checks do not establish Apple-device performance. Linux WebKit can log framebuffer validation messages while rendering. Browser play requires WebGL 2 and an HTTPS host or localhost.

Windows, macOS and Linux ARM64 gameplay were not rerun for this release. Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. Direct3D 12 with AMD FSR requires the Microsoft Visual C++ x64 runtime.
