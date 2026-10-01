# Abyssal Engine 1.15.0 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

The engine regression suites and Python source/package tests were run on Linux x86-64 with Godot 4.7 and locally supplied compatible content, headless on the OpenGL (Compatibility) renderer. `ocean_atmosphere_check` and `ocean_options_check` report failures that occur identically on the 1.12.0 to 1.14.0 sources. `engine_ui_check` now covers the reticle on the hull's line of fire, convergence under it, the hull readout and low-hull pulse with their switches, and lighter feedback for shield hits than hull hits.

Aim was measured in the real game from the chase camera with the starting harpoon: before, it left 126 px under the screen-centre reticle and was still 38 px low at 100 m; now it climbs from the bow into the reticle and meets it at 204.8 m. Damage feedback was captured with shield-only and hull damage on the Compatibility renderer.

The burst shader change targets browsers that run WebGL through Direct3D (Windows). On this machine the old and new shaders render alike; the fix has not been run on Windows.

## Platform status

Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives; this release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon.

The browser package uses WebGL 2. No physical phone, mobile browser or physical gamepad was tested for this release. The translations were machine-written and checked for structure, not reviewed by native speakers.
