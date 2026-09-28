# Abyssal Engine 1.9.0 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

The engine regression suites and Python source/package tests were run on Linux x86-64 with Godot 4.7 and locally supplied compatible content. `ocean_atmosphere_check` and `ocean_options_check` each report one assertion (regional water clarity; regional water applied while paused) that fails identically on the 1.8.0 source; they are not caused by this release. New coverage (`graphics_quality_check`): preset read/write and Custom detection, 1.8.0 resolution migration, presets leaving resolution alone, render-scale arithmetic, the detection pass rules and floor, first-start detection with its dialog, recommendation for profiles that already had a preset, dropdown open/close, station-lamp shadow modes per level on the Compatibility and Forward+ renderers, the FPS counter, the headlight brightness setting, sliders ignoring the mouse wheel, and touch drag-scrolling of the title's settings from a row.

Graphics cost was measured in-game beside a station on an RTX 3090 with the Forward+, Mobile and Compatibility renderers. These are relative desktop figures, not phone frame rates. First-start detection was run on the GPU with all three renderers.

## Platform status

Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives; this release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon.

Detection has not been run on a physical phone or in a mobile browser. Where a browser does not report GPU timings, detection relies on a steady 60 frames per second alone.

The Mobile renderer prints Godot rendering-device errors on this desktop at the title, identically in 1.8.0.

The browser package uses WebGL 2. A physical iPhone was not available, so desktop browser checks do not establish iOS compatibility.
