# Abyssal Engine 1.3.0 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

The 19 engine regression suites and 37 Python source/package tests passed on Linux x86-64 with Godot 4.7 and locally supplied compatible content. Coverage includes the station chart zone and side view, separate and shared S.T.R.E.A.M. gates (placement clearance at six spacings, arrival/departure slots, confirming at a partly open gate), the recent-trips trail and its save round trip, loading saves written before the trail existed, grid-square world spacing, the manta wing beat, touch drags over buttons, continuous travel, campaign encounters, collision, touch/gamepad input and menus.

The Linux x86-64 build was launched in Vulkan Forward+. The station chart, gate labels, gate aperture placement and preview lighting were checked in GPU captures.

## Platform status

Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives; this release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon.

The browser package uses WebGL 2. A physical iPhone was not available, so desktop browser checks do not establish iOS compatibility.

Android uses version code 37 and the existing release signing key for updates that preserve imported content and saves.
