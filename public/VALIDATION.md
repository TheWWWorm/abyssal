# Abyssal Engine 1.10.0 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

The engine regression suites and Python source/package tests were run on Linux x86-64 with Godot 4.7 and locally supplied compatible content. `ocean_atmosphere_check` and `ocean_options_check` each report one assertion (regional water clarity; regional water applied while paused) that fails identically on the 1.9.0 source; they are not caused by this release. New coverage: music replacement install, format detection, playback switch and restore (`mods_check`); the tested beam pass's render modes and camera-near selection (`engine_stream_check`); a failure page waiting for the explosion that caused it (`engine_ui_check`); the Android vibrate permission (`test_platform_tools`).

The map layout was checked in touch mode at 1280×570, 1280×592, 1280×720 and 1100×520, and on desktop at 1280×600 and 1920×1080. Beam occlusion by the player's hull was checked on the Forward+, Mobile and Compatibility renderers, including a simulated failed depth read.

## Platform status

Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives; this release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon.

The Android audio picker (`AbyssalImporter.choose_audio`) and vibration have not been run on a physical phone.

The browser package uses WebGL 2. A physical iPhone was not available, so desktop browser checks do not establish iOS compatibility.
