# Abyssal Engine 1.6.1 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

The 19 engine regression suites and 37 Python source/package tests passed on Linux x86-64 with Godot 4.7 and locally supplied compatible content. New coverage: a two-answer question (travel outside the safety zone) fits on one sheet at 1280x720.

The Linux x86-64 build was launched in Vulkan Forward+. The contracts board, the travel confirmation and the ship dealer's showroom (drag to turn) were checked in GPU captures at 1920x1080.

## Platform status

Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives; this release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon.

The browser package uses WebGL 2. A physical iPhone was not available, so desktop browser checks do not establish iOS compatibility.

Android uses version code 41 and the existing release signing key for updates that preserve imported content and saves.
