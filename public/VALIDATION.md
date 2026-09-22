# Abyssal Engine 1.2.4 — platform support

The gameplay and rendering checks ran on Linux x86-64 with Godot 4.7 and
a locally imported compatible DEEP JAR. Game content is not included in the
packages.

## Validation

- All 15 engine regression suites passed headless, including 185 gameplay
  assertions, 50 coordinate assertions, 765 mission assertions across all
  48 story chapters, sustained travel, STREAM transfers, terrain and UI.
- Coordinate checks cover capsule ascent, sinking wrecks, floating fish,
  mine bobbing, formations, reinforcement routes, finale motion and camera
  placement. Towing, salvage limits, projectile direction and copied native
  routes are covered as well.
- Both hangars were checked with crisp and smoothed textures, classic and
  enhanced rendering, and closed, partially open and fully open doors.
  The 32 focused rendering assertions passed on OpenGL Compatibility and
  Vulkan Forward+ on an NVIDIA RTX 3090.
- The updated STREAM test passed on OpenGL Compatibility, including the
  visible portal orientation and the actual arrival heading.

## Scope and limitations

Windows, macOS, Linux ARM64 and Android gameplay were not run on their target
systems for this release. Cross-platform export and archive checks do not
establish device performance or full-game compatibility. Windows and macOS
packages are unsigned, and macOS is not notarized.

The broader OpenGL rendering suite still has eight headlight assertions
that also fail in the previous source, along with shader-instance-buffer
exhaustion in its large test scene. The focused door and gate rendering
checks pass without those errors.

Android uses version code 28 and the existing release signing key, allowing
in-place updates that preserve imported content and saves.
