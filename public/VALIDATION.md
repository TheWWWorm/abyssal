# Abyssal Engine 1.6.2 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

The 19 engine regression suites and 37 Python source/package tests passed on Linux x86-64 with Godot 4.7 and locally supplied compatible content. No new test coverage; the change is a layout position.

The Linux x86-64 build was launched in Vulkan Forward+. The catch line and struggle bar were checked below the hull in GPU captures at 1920x1080, 1280x720, 2000x920 and 920x2000.

## Platform status

Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives; this release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon.

The browser package uses WebGL 2. A physical iPhone was not available, so desktop browser checks do not establish iOS compatibility.

Android uses version code 42 and the existing release signing key for updates that preserve imported content and saves.
