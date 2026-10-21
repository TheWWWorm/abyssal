# Abyssal 1.21.7 — platform support

A compatible DEEP JAR must be supplied separately. Original game assets and data are not included in the downloads.

## Browser import

JAR conversion passed in WebKit 26.5 and Chromium 151 on Linux, including a JAR with a different filename and uppercase extension, rejection of an invalid archive, and subsequent retry. The original picker lifetime failure was reproduced in WebKit. The fixed picker remained available while the file chooser was open.

The compiled 1.21.7 Web build imported a supplied JAR from its main menu in WebKit, displayed the imported 3D title scene and enabled Start new game. The 46 Python checks include seven JavaScript checks for picker lifetime, cancellation, repeated selection, file errors and late converter responses.

## Packages

All six platform packages were exported from the same source. The Linux x86-64 package passed rendered Vulkan and OpenGL startup checks and packaged UI and version checks. The Linux x86-64 and ARM64 executables retain the portable 1.21.6 runtimes and require no glibc symbols newer than 2.28.

The Android APK uses the existing release certificate, passes signature and 16 KiB alignment verification, and identifies itself as org.abyssal.engine version 1.21.7, version code 79. It requests no network or broad storage permission. Package contents, the source archive and SHA-256 checksums are verified before publication.

The station-rendering runtimes and Windows AMD FidelityFX runtime are unchanged from 1.21.6. This release changes the browser file picker and its cleanup; gameplay and rendering settings are unchanged.

## Platform limits

Physical iPhone, iPad and macOS Safari were not tested. The browser checks use Linux WebKit and Chromium; they do not establish Apple-device compatibility or performance. Linux WebKit rendered the title but logged framebuffer validation messages. Browser play requires WebGL 2 and an HTTPS host or localhost.

Windows, macOS, Linux ARM64 and Android gameplay were not rerun for this browser fix. Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. Direct3D 12 with AMD FSR requires the Microsoft Visual C++ x64 runtime. A build or signature check does not establish native device performance.
