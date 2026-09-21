# Platform support

## What was actually run

Checks were run on Linux x86-64 with Godot 4.7.stable, headless on the OpenGL
compatibility renderer, and by rendered captures read back from a real GPU
(RTX 3090) on the Vulkan Forward+ renderer, using a locally imported DEEP content
cache.

- Engine regression suite: **14 of 14 checks passed** headless on OpenGL
  (`tools/check.py --compatibility`), including new checks for the bank
  profile, the lamp lights (one per sprite, per bone, off while the station's
  animation has the bone shrunk away), the lure point, and the bent head.
- Python packaging, importer and distribution tests: **36 of 36 passed**.
- The anglerfish was captured swimming, tracked over four seconds from the side
  and the front quarter, with the neck closed in every frame; the devilfish and
  marlin at both swing extremes; the hangar's berth-lamp chase over a hundred
  frames from a fixed camera with the blue spill on the deck coming and going
  with the sprites; the engine's red lamp on its rotor.
- Two Linux x86-64 test packages built from the tree during the work were
  extracted and played by the requester, whose reports shaped the lamp change.
- Windows, macOS, Linux x86-64, Linux ARM64, Web and Android packages all exported.
- The Android APK is signed with the same release key as every build since
  preview.2 and carries version code 26, so it updates earlier builds in place.

## What was not validated

- **The Android package was not installed or run**: the build host has no
  `/dev/kvm` and its emulator no GPU. The Mobile renderer's handling of the new
  per-instance shader uniform (the bent head) and of a dozen unshadowed omni
  lights on a hangar was not seen on a device.
- Windows, macOS, Linux ARM64 and browser packages were exported but not launched.
  The browser's WebGL 2 renderer was not exercised with the per-instance uniform.
