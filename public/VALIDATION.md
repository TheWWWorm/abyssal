# Platform support

## What was actually run

Checks were run on Linux x86-64 with Godot 4.7.stable, headless on the OpenGL
compatibility renderer, and by rendered captures read back from a real GPU
(RTX 3090) on the Vulkan Forward+ renderer, using a locally imported DEEP content
cache.

- Engine regression suite: **14 of 14 checks passed** headless on OpenGL
  (`tools/check.py --compatibility`), including the rewritten gameplay, story
  layout, market, contract, session, UI and stream checks.
- Python packaging, importer and distribution tests: **36 of 36 passed**.
- Every story chapter's layout (ship and special-object counts), every contract
  kind, the chapter-47 finale, station rounds, pirate odds over 40 seeds and the
  twenty-creature habitat were checked headless against the original's rules.
- Three contracts were driven end to end through the real UI on the GPU: accept
  from the job board with deposit, depart, autopilot to the holding, waypoint,
  gang wake, completion radio, reward and dock unlock.
- The Help pages, load slots, save slots, job board card and loading tips were
  each checked by captures from the GPU, as were twenty creatures in the water,
  the anglerfish and whale belly-down while fleeing, and the showroom's first
  frame after a ship switch.
- A Linux x86-64 test package built from the same tree was extracted and launched
  from its own data directory: it starts on Vulkan Forward+.
- Windows, macOS, Linux x86-64, Linux ARM64, Web and Android packages all exported.
- The Android APK is signed with the same release key as every build since
  preview.2 and carries version code 24, so it updates earlier builds in place.

## What was not validated

- **The Android package was not installed or run.** This release switches the
  Android export to the Mobile renderer on Vulkan (OpenGL ES fallback). It builds
  and is correctly signed, but nothing was executed on Android; the build host
  exposes no `/dev/kvm` and its emulator has no GPU, so the Vulkan path is untested
  on a device.
- Windows, macOS, Linux ARM64 and browser packages were exported but not launched.
- Gamepad vibration and Android vibration were exercised only by code path, not
  felt on hardware.
- Save migration from 1.1.1 was checked by the session tests' reseed rule, not by
  loading a long-played 1.1.1 save.
