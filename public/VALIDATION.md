# Platform support

## What was actually run

Checks were run on Linux x86-64 with Godot 4.7.stable, headless on the OpenGL
compatibility renderer, and by rendered captures read back from a real GPU
(RTX 3090) on the Vulkan Forward+ renderer, using a locally imported DEEP content
cache.

- Engine regression suite: **14 of 14 checks passed** headless on OpenGL
  (`tools/check.py --compatibility`).
- Python packaging, importer and distribution tests: **36 of 36 passed**.
- Every creature species was captured side on from the GPU, body and tail parts
  together, and its orientation confirmed by the requester.
- The depth-limit markers, the Mods · Textures page (list, view, replace, restore,
  live reload on the station behind the menu with a 4x atlas), the gold interface
  at the dock and in flight, the docked water in motion, a sunk vessel's lamps,
  the girder joints and overlapping girders at Salty Void, and the one-Back menu
  pages were each checked by captures from the GPU.
- Pirates were simulated against a stationary player for sixty seconds: constant
  speed, strafing passes, no stopping.
- A Linux x86-64 test package built from the same tree was extracted and launched.
- Windows, macOS, Linux x86-64, Linux ARM64, Web and Android packages all exported.
- The Android APK is signed with the same release key as every build since
  preview.2 and carries version code 25, so it updates earlier builds in place.
  The importer plugin's new image picker compiled into it.

## What was not validated

- **The Android package was not installed or run.** Its tilt-steering fix (the
  project now asks for the accelerometer and gravity sensors), the Mobile
  renderer on Vulkan, and the Mods page's document picker are built and signed
  but untested on a device; the build host has no `/dev/kvm` and its emulator no
  GPU.
- Windows, macOS, Linux ARM64 and browser packages were exported but not launched.
- Content caches imported by earlier versions keep their raw `.bmp` and
  `.alpha.png` texture files; the game no longer reads them. The one-file keying
  was checked against a fresh import's PNGs and a 4x replacement.
