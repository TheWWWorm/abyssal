# Abyssal Engine 1.15.1 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

Seven Godot 4.7 regression suites passed on Linux x86-64: engine UI, STREAM travel, readability, platform input (318 checks), gamepad UI (67 checks), engine language, and modern gameplay (186 checks).

Touch-event checks exercise the actual Trade and Workshop rows in portrait and landscape, starting swipes on backgrounds, icons, names, descriptions and prices. Subsequent taps still select items. Translated HUD and warning layouts were checked in all 15 interface languages, including narrow-screen warnings.

The chase-camera and weapon convergence checks cover 11 hulls, three aspect ratios and five orientations. Linux desktop OpenGL checks cover repeated language changes at the title and in-game settings, translated HUD rendering, warning arrows, and damage effects extending over the complete portrait and landscape viewport.

The translation catalog checker reports 891 source texts and 14 catalogs with no structural problems. Translations have not been reviewed by native speakers.

## Platform status

The Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives. This release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon. Android uses the existing release signing key.

The browser package uses WebGL 2. No physical phone, mobile browser or physical gamepad was tested for this release. The language-change error was reproduced and corrected on Linux desktop; the original report did not establish which platform was affected.
