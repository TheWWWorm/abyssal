# Abyssal 1.21.11 — platform support

A compatible DEEP JAR must be supplied separately. Original game assets and data are not included in the downloads.

## What was checked

The 46 Python checks passed, and so did all 26 native checks. The native checks cover content and startup, engine UI, controller and keyboard menu navigation, readability, graphics settings, world spacing, platform input, ocean options, stream travel, open-world missions, coordinates and the reference wiki. New checks cover the freelance board's location preview, the stations ringed by Range on chart, radar pictures for cargo and creatures, and the story's docking refusals in chapters 5 and 6.

The compiled Web build imported a supplied JAR in Linux WebKit with no script errors.

## Packages

All six platform packages were exported from the same source. Linux x86-64 passed rendered Vulkan and OpenGL startup checks and packaged UI and version checks. Linux x86-64 and ARM64 retain the portable 1.21.6 runtimes and require no glibc symbols newer than 2.28.

The Android APK uses the existing release certificate and passes signature and 16 KiB alignment verification. It identifies itself as org.abyssal.engine version 1.21.11, version code 83, and requests no network or broad storage permission. Package contents, the source archive and SHA-256 checksums are verified before publication.

The station-rendering runtimes and Windows AMD FidelityFX runtime are unchanged from 1.21.6.

## Platform limits

This release was not run on an Android device, physical iPhone or iPad, or macOS Safari. Linux WebKit checks do not establish Apple-device performance. The Range on chart picker and radar pictures were checked by automated tests and desktop screenshots, not by hand on a touchscreen. Browser play requires WebGL 2 and an HTTPS host or localhost.

Windows, macOS and Linux ARM64 gameplay were not rerun for this release. Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. Direct3D 12 with AMD FSR requires the Microsoft Visual C++ x64 runtime.
