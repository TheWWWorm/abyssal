# Abyssal Engine 1.2.8 — platform support

The gameplay checks ran on Linux x86-64 with Godot 4.7 and a locally supplied
compatible DEEP JAR. Game content is not included in the packages.

## Validation

- A fresh portable import of the compatible JAR completed and produced a usable
  content pack. The regression check covers converted BMP textures when the
  original BMP is absent, which caused fresh Android imports to fail.
- The Android importer transport check and 20 Python import, publication and
  class-data checks passed.
- The engine stream checks passed headless and with the Forward+ renderer.
  Focused station-light occlusion and angler-lure alignment renders passed in
  Forward Mobile, Forward+ and OpenGL Compatibility.
- A Linux x86-64 package made from this source was unpacked. Its bundled
  importer converted the compatible JAR, the engine loaded that pack, and the
  packaged executable launched for 120 headless frames.

## Scope and limitations

The complete OpenGL Compatibility stream suite is not a release gate on this
machine: it has existing headlight image thresholds and a shader-instance
buffer limit also present in 1.2.6. The new focused rendering checks passed.

Windows, macOS, Linux ARM64 and Android gameplay were not run on their target
systems for this release. In particular, a fresh import was not tested on an
Android device. Cross-platform export and archive checks do not establish
device performance or full-game compatibility. Windows and macOS packages are
unsigned, and macOS is not notarized.

Android uses version code 32 and the existing release signing key, allowing
in-place updates that preserve imported content and saves.
