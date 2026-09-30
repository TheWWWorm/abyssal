# Abyssal Engine 1.12.0 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

The engine regression suites and Python source/package tests were run on Linux x86-64 with Godot 4.7 and locally supplied compatible content, headless on the OpenGL (Compatibility) renderer. `ocean_atmosphere_check` and `ocean_options_check` report failures that occur identically on the 1.11.0 source. `engine_ui_check`, `readability_check`, `platform_input_check` and `gamepad_ui_check` cover the scrolling lists, the kept list offset, stick roles, holding D-pad left to look, and chart zoom and pan on a pad.

Station menus (shop, ship equipment, trade, saves, help, medals) were captured at 960×432 and 1280×570 with touch controls and at 1600×900 on the desktop layout, with a station's stock padded to 14 rows to exercise scrolling.

## Platform status

Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives; this release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon.

The browser package uses WebGL 2. No physical phone, mobile browser or physical gamepad was tested for this release.
