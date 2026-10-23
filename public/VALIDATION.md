# Abyssal 1.21.12 — platform support

Supply a compatible DEEP JAR separately. Original game assets and data are not included in the downloads.

## Checks

All 28 headless regression suites and 46 Python tests pass. They cover navigation, save transfer, keyboard and controller input, STREAM travel, hull handling and depth markers. The main-menu save test also passes against the compiled Linux package. Running the supplied original JAR confirms map selection stages, immediate autopilot disengagement, preserved thrust when cancelling STREAM, Fire skipping the arrival camera and active-encounter OUT-gate locks.

The Near limits panel was rendered at four times its former distance with matching brightness. The GPU regression suite reports four hangar-door probe failures that also occur on the unchanged 1.21.11 source; the new depth checks pass.

The compiled Web build imported a supplied JAR in Linux WebKit. From an empty Load menu it imported a portable save and downloaded an export with identical save contents.

## Packages

All six platform packages are exported from the same source. Linux x86-64 passes rendered Vulkan and OpenGL startup and packaged UI/version checks. Linux x86-64 and ARM64 retain the portable runtimes used since 1.21.6 and require no glibc symbols newer than 2.28. The station-rendering engines and Windows AMD FidelityFX runtime are unchanged.

The Android APK passes signature and 16 KiB alignment verification, uses the existing release certificate, identifies itself as org.abyssal.engine version 1.21.12, version code 84, and requests no network or broad storage permission. Package contents, source inventory and SHA-256 checksums are verified before publication.

## Platform limits and known issue

Intermittent white flashes while firing remain unresolved. They did not reproduce on an NVIDIA RTX 3090 under Linux using the release engine. Windows Direct3D 12, upscaling and frame generation were not exercised for this report.

Windows, macOS and Linux ARM64 gameplay were not rerun for this release. Windows and macOS packages are unsigned; macOS is not notarized. Direct3D 12 with AMD FSR requires the Microsoft Visual C++ x64 runtime. This release was not run on an Android device, physical iPhone or iPad, or macOS Safari. Linux WebKit checks do not establish Apple-device performance. Browser play requires WebGL 2 and an HTTPS host or localhost.
