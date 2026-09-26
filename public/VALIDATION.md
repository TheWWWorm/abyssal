# Abyssal Engine 1.7.0 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

The 19 engine regression suites and 37 Python source/package tests passed on Linux x86-64 with Godot 4.7 and locally supplied compatible content. New coverage: the shared settings screen (tabs, LB/RB, submenus without values, key rebinding, focus return), menu music choice and fallbacks, the browser fullscreen corner button, and settings panel sizing on short windows.

The Linux x86-64 build was launched. The settings screen was checked in GPU captures from the main menu, pause menu and station at 1920x1080 and on an upright 540x1170 window; the title menu upright at 540x1170. Map controller input (stick, LB/RB, triggers, focus) was checked with simulated pad input.

The 1.0.3 music table (intro.mid, station.mid) was read from a Russian 1.0.3 JAR, which imports with this version.

## Platform status

Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives; this release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon.

Android now follows the device sensor in every direction (previously fixed landscape). This was not tested on a physical device.

The browser package uses WebGL 2. A physical iPhone was not available, so desktop browser checks do not establish iOS compatibility.

Android uses version code 43 and the existing release signing key for updates that preserve imported content and saves.
