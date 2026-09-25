# Abyssal Engine 1.6.0 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

The 19 engine regression suites and 37 Python source/package tests passed on Linux x86-64 with Godot 4.7 and locally supplied compatible content. New coverage: travel to a station outside the hull's safe depth asks for confirmation (cancel keeps no course, confirming sets it); the equipment shop's ship line opens the ship page and Back returns to the shop; the station menu fits 720p without a scrollbar in touch and desktop modes; shop, workshop and trade details fit at 720p for every stocked item; the trade and workshop actions still buy, sell and manufacture.

The Linux x86-64 build was launched in Vulkan Forward+. The station menus, main menu, contracts, trade, journal and the desktop and touch flight HUD were checked in GPU captures at 1920x1080, 2000x920 and 920x2000.

## Platform status

Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives; this release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon.

The browser package uses WebGL 2. A physical iPhone was not available, so desktop browser checks do not establish iOS compatibility.

Android uses version code 40 and the existing release signing key for updates that preserve imported content and saves.
