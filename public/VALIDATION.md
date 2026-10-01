# Abyssal Engine 1.13.0 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

The engine regression suites and Python source/package tests were run on Linux x86-64 with Godot 4.7 and locally supplied compatible content, headless on the OpenGL (Compatibility) renderer. `ocean_atmosphere_check` and `ocean_options_check` report failures that occur identically on the 1.12.0 source. The new `engine_language_check` covers language detection for English, Russian, Ukrainian, German, Chinese, Japanese and Korean text, Auto and chosen-language resolution, loading every catalog, and glyph coverage of the bundled CJK fonts. `test_engine_text` checks that all 14 catalogs hold every marked text with the same placeholders.

The title, Settings, flight HUD and pause menu were captured at 1280×720 with the Russian 1.0.3 JAR on Auto, and with the English 1.0.8 JAR set to Japanese and to German. A web export was checked with the pack verifier; it contains the catalogs and the three font subsets.

## Platform status

Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives; this release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon.

The browser package uses WebGL 2. No physical phone, mobile browser or physical gamepad was tested for this release. The translations were machine-written and checked for structure, not reviewed by native speakers.
