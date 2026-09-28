# Abyssal Engine 1.11.0 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

The engine regression suites and Python source/package tests were run on Linux x86-64 with Godot 4.7 and locally supplied compatible content, headless on Forward+ and on the OpenGL (Compatibility) renderer. `ocean_atmosphere_check` and `ocean_options_check` each report one assertion (regional water clarity; regional water applied while paused) that fails identically on the 1.10.1 source. `readability_check` now checks that the wake starts at an engine outlet.

The title menu was captured at 1920×1080, 1921×1081 and 5120×2880 fullscreen on an RTX 3090. All eleven original hulls were rendered in flight from the front, side, stern and below to check window, tail-lamp and engine-glow placement, and the wake outlets were checked on orthographic stern views.

## Platform status

Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives; this release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon.

The browser package uses WebGL 2. No physical phone or mobile browser was measured for this release.
