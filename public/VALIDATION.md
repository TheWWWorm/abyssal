# Abyssal Engine 1.16.0 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

Python unit tests (41) passed on Linux x86-64. Of the 23 Godot regression checks, 21 passed. Both failures are in the ocean atmosphere and ocean options checks. These failed identically on the 1.15.1 source with the same content cache and are unrelated to this release.

A save made at one aspect ratio and loaded at another was checked on Linux desktop (Vulkan) at 21:9, 4:3 and auto. In 1.15.1 this recursed between the title's and the game's resize handlers until video memory was exhausted. In 1.16.0 all three loads complete.

The algae cut-out change was compared in Linux desktop renders at about 25 m and 90 m. Pale square blocks from the white key are gone at both distances. The mods check covers replacement atlases, original texel addressing and the keyed atlas.

The translation catalog checker reports 898 source texts and 14 catalogs with no structural problems. New strings were not reviewed by native speakers.

## Platform status

The Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives. This release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon. Android uses the existing release signing key.

The browser package uses WebGL 2. No physical phone, mobile browser or physical gamepad was tested for this release.
