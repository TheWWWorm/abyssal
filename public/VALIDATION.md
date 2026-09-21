# Platform support

## What was actually run

Checks were run on Linux x86-64 with Godot 4.7.stable, headless on the OpenGL
compatibility renderer, and by rendered captures read back from a real GPU
(RTX 3090) on the Vulkan Forward+ renderer, using a locally imported DEEP content
cache.

- Engine regression suite: **14 of 14 checks passed** headless on OpenGL
  (`tools/check.py --compatibility`), including a new check that the
  anglerfish's lure lamp sits on the bent rod tip while the head swings, and
  returns to its rest when the bend is cleared.
- Python packaging, importer and distribution tests: **36 of 36 passed**.
- The anglerfish was captured swimming from above, twelve frames over three
  seconds with the head bent up to eleven degrees, the lure's halo on the rod
  tip in every frame; the lamp's position was also logged against the bend
  each ten frames (up to 0.94 m of sideways travel at the full bend, matching
  the shader's turn of the tip).
- The 1.2.2 build was played by the requester, whose report of the lure
  hanging beside the tip is the fix in this build.
- Windows, macOS, Linux x86-64, Linux ARM64, Web and Android packages all exported.
- The Android APK is signed with the same release key as every build since
  preview.2 and carries version code 27, so it updates earlier builds in place.

## What was not validated

- **The Android package was not installed or run**: the build host has no
  `/dev/kvm` and its emulator no GPU. The Mobile renderer's handling of the new
  per-instance shader uniform (the bent head) and of a dozen unshadowed omni
  lights on a hangar was not seen on a device.
- Windows, macOS, Linux ARM64 and browser packages were exported but not launched.
  The browser's WebGL 2 renderer was not exercised with the per-instance uniform.
