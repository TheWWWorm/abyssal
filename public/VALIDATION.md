# Abyssal Engine 1.10.1 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

The engine regression suites and Python source/package tests were run on Linux x86-64 with Godot 4.7 and locally supplied compatible content. `ocean_atmosphere_check` and `ocean_options_check` each report one assertion (regional water clarity; regional water applied while paused) that fails identically on the 1.10.0 source. Run on the OpenGL (Compatibility) renderer with a GPU, `engine_stream_check` reports the same 8 headlight-surface assertions as on the 1.10.0 source; it passes headless and on Forward+. New coverage: the shared water-colour map, shadow budgets per level and their nearest-first choice (`graphics_quality_check`), station lamps ignoring moving casters while station walls still shade (`engine_stream_check`), the close-up detection view, its pixel margin and re-measuring an earlier recommendation (`graphics_quality_check`).

Rendering cost was measured in game with a station filling the screen, on an RTX 3090 with the Compatibility renderer at 5244×2412 (four times an iPhone 17 Pro's pixels, which keeps the GPU at full clock). These are relative desktop figures, not phone frame rates. Before/after captures of the water-colour change are identical apart from animated sprites and wildlife; Forward+ captures were compared as well.

## Platform status

Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives; this release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon.

The browser package uses WebGL 2. The changes target phones and browsers, but no physical phone or mobile browser was measured for this release.
