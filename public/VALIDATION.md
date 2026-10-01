# Abyssal Engine 1.14.0 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

The engine regression suites and Python source/package tests were run on Linux x86-64 with Godot 4.7 and locally supplied compatible content, headless on the OpenGL (Compatibility) renderer. `ocean_atmosphere_check` and `ocean_options_check` report failures that occur identically on the 1.12.0 and 1.13.0 sources. `engine_language_check` now also covers text with no detectable language falling back to the system locale.

The first-start language question was run with the English 1.0.8 JAR, fresh settings and the system locale set to de_DE. Both answers were exercised: Deutsch stores `interface/language=de` and redraws the title in German; English stores `auto`, closes the dialog and starts the graphics measurement. Neither asks again.

## Platform status

Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives; this release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon.

The browser package uses WebGL 2; there the system language is the browser's language. No physical phone, mobile browser or physical gamepad was tested for this release. The translations were machine-written and checked for structure, not reviewed by native speakers.
