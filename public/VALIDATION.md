# Abyssal Engine 1.5.0 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

The 19 engine regression suites and 37 Python source/package tests passed on Linux x86-64 with Godot 4.7 and locally supplied compatible content. Coverage includes phone margins in landscape and portrait, touch control spacing at 800x600, 1280x720, 1140x589, 2400x1080 and 589x1184, touch input on an inset overlay, camera orbit from a touch drag (hold, recentre on stick contact, timeout), the fixed steering stick, inverted stick pitch, the harpoon's place on a ship without guns after the placement editor, the portrait field of view, continuous travel, campaign encounters, collision, touch/gamepad input and menus.

The Linux x86-64 build was launched in Vulkan Forward+. The touch HUD at 2000x920 and 920x2000 (19.5:9 phone, landscape and portrait), the station menu and the pause menu were checked in GPU captures.

## Platform status

Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives; this release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon.

The browser package uses WebGL 2. A physical iPhone was not available, so desktop browser checks do not establish iOS compatibility; safe-area insets are read from CSS `env(safe-area-inset-*)`.

Android uses version code 39 and the existing release signing key for updates that preserve imported content and saves.
