# Abyssal Engine 1.17.0 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

Python unit tests (41) passed on Linux x86-64. Of the 23 Godot regression checks, 21 passed on the Compatibility renderer. Both failures are in the ocean atmosphere and ocean options checks; they fail identically on the 1.16.1 source with the same content cache and are unrelated to this release. The graphics quality check also passed headless on Forward+, and its upscaler steps passed on Vulkan (RTX 3090): FSR 2.2 at 50% and 100% 3D resolution, FSR 1.0 at 50%, and bilinear at 100% with FSR 1.0 chosen.

MetalFX could not be run: no current build uses the Metal driver, so those modes are not offered in any package.

## Platform status

The Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives. This release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon. Android uses the existing release signing key.

The browser package uses WebGL 2. No physical phone, mobile browser or physical gamepad was tested for this release.
