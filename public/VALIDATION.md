# Platform support

## What was actually run

Checks were run on Linux x86-64 with Godot 4.7.stable, headless on the OpenGL
compatibility renderer, and by rendered captures read back from a real GPU
(RTX 3090) on the Vulkan Forward+ renderer, using a locally imported DEEP content
cache.

- Engine regression suite: **14 of 14 checks passed** headless on OpenGL
  (`tools/check.py --compatibility`).
- Python packaging, importer and distribution tests: **36 of 36 passed**.
- The title menu, its station backdrop and the loading notice, the opening
  sequence at eight moments including its hand-over to the chase camera beside
  the hull, and the manta, whale, anglerfish and jellyfish at four phases of
  their motion were each checked by captures from the GPU.
- Creature motion ranges were checked numerically over 400 ticks per species:
  scales and body swings stay within the original's bounds and do not drift.
- Every sound trigger and every animated element was audited against the
  decompiled original; the audit and the list of deliberate replacements are
  recorded outside the repository.
- A Linux x86-64 test package built from the same tree was extracted and launched
  from its own data directory: it starts on Vulkan Forward+ and shows the new title.
- Windows, macOS, Linux x86-64, Linux ARM64, Web and Android packages all exported.
- The Android APK is signed with the same release key as every build since
  preview.2 and carries version code 22, so it updates earlier builds in place.

## What was not validated

- **The Android package was not installed or run.** It builds and is correctly
  signed, but nothing in this release has been executed on Android; the build host
  exposes no `/dev/kvm`, so the x86-64 emulator cannot start.
- Windows, macOS, Linux ARM64 and browser packages were exported but not launched.
  The browser's music transport was exercised only by its own unit test.
- The opening was watched only as captured stills, not as a continuous run.
