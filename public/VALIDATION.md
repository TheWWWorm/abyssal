# Abyssal Engine 1.4.0 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

The 19 engine regression suites and 37 Python source/package tests passed on Linux x86-64 with Godot 4.7 and locally supplied compatible content. Coverage includes the redesigned touch HUD (dock button availability, unfitted gear, throttle arc, harpoon in the guns' place, placement editor), manual and autopilot S.T.R.E.A.M. gate entry, gate and station push-back including a head-on approach, headlight beams stopped by creatures and vessels but not by their own hull, chart zone dragging with mouse and touch, contract destinations on the chart, medal pages on docking, continuous travel, campaign encounters, collision, touch/gamepad input and menus.

The Linux x86-64 build was launched in Vulkan Forward+. The touch HUD at 1672x941, 800x600 and 2400x1080, the gate prompt, the chart, the medal pages and the beam occlusion were checked in GPU captures.

## Platform status

Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives; this release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon.

The browser package uses WebGL 2. A physical iPhone was not available, so desktop browser checks do not establish iOS compatibility.

Android uses version code 38 and the existing release signing key for updates that preserve imported content and saves.
