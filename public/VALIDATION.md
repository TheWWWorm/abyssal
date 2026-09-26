# Abyssal Engine 1.7.1 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

The 19 engine regression suites and 37 Python source/package tests passed on Linux x86-64 with Godot 4.7 and locally supplied compatible content. New coverage: every settings tab and Controls page fits touch canvases of 540, 591 and 634 by 1280 and 1280 by 720, with the tabs in one row only on the landscape canvas.

The settings screen was checked in GPU captures of the main menu and the pause menu on a 390x787 window (an iPhone browser with its bars, 634x1280 touch canvas).

## Platform status

Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives; this release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon.

Android follows the device sensor in every direction. This was not tested on a physical device.

The browser package uses WebGL 2. A physical iPhone was not available, so desktop browser checks do not establish iOS compatibility.
