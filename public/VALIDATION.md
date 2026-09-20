# Platform support

## What was actually run

Checks were run on Linux x86-64 with Godot 4.7.stable, headless on the OpenGL
compatibility renderer and on a real GPU (RTX 3090) on the Vulkan Forward+ renderer,
using a locally imported DEEP content cache.

- Engine regression suite: **14 of 14 checks passed** headless on OpenGL
  (`tools/check.py --compatibility`) and **14 of 14 on the GPU** on Vulkan
  (`tools/check.py --gpu`). The gamepad/touch check is sensitive to a real mouse
  pointer resting over the test window on this desktop and was passed standalone.
- Python packaging, importer and distribution tests: **36 of 36 passed**.
- The station generator was compared against the layouts recorded from the original
  for all **200 stations: 1490 parts, no differences** in model ids or transforms.
- The Linux x86-64 package was extracted and launched from its own data directory: it
  starts on Vulkan Forward+ and logs no errors. This is the first release whose Linux
  and Windows packages run Forward+; every earlier preview ran OpenGL, where volumetric
  light, shading detail and temporal antialiasing never applied.
- Frame cost was measured near a fully lit station at native 5120x2880: 9 ms on Vulkan
  at 150 m from Gosu, 4 ms in open water.
- Headlights, beams, station orientation, the departure shot, the reticle and the
  harpoon, the free-look camera and the mods folder were each checked by rendered
  captures read back from the GPU, and by assertions in the suite.
- Windows, macOS, Linux x86-64, Linux ARM64, Web and Android packages all exported.
- The Android APK is signed with the same release key as every preview since preview.2
  and carries version code 21, so it updates earlier previews in place.

## What was not validated

- **The Android package was not installed or run.** It builds and is correctly signed,
  but nothing in this release has been executed on Android. The build host exposes no
  `/dev/kvm`, so the x86-64 emulator cannot start.
- Windows, macOS, Linux ARM64 and browser packages were exported but not launched. No
  gameplay, fresh JAR import or save transfer was exercised on those platforms. A
  Windows machine without a Vulkan driver falls back to OpenGL by the project's own
  setting; that fallback was not exercised.
- **Steer by tilting** (Controls · Steering) has never been run on a device.
- The frame-rate numbers are from one machine at one resolution.
