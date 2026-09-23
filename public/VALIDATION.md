# Abyssal Engine 1.2.12 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

The engine regression suites and Python source/package tests passed on Linux x86-64 with Godot 4.7 and locally supplied compatible content. Coverage includes saved spacing preferences, all six spacing options, metre/kilometre labels, gate clearance, banking direction, continuous travel, S.T.R.E.A.M. transfers, campaign encounters, collision, touch/gamepad input and menus.

The Linux x86-64 release was launched with prepared content using Vulkan Forward+. The settings and flight labels were visually checked. Source and archive checks verify the engine-only distribution boundary and offline importer contents.

## Platform status

Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives; this release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon.

The browser package uses WebGL 2. A physical iPhone was not available, so desktop browser checks do not establish iOS compatibility.

Android uses version code 36 and the existing release signing key for updates that preserve imported content and saves.
