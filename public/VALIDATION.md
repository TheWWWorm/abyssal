# Abyssal Engine 1.2.10 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

- The 15 engine regression suites passed on Linux x86-64 with Godot 4.7 and
  locally supplied compatible content. They cover docking presentation, gate
  streaming and rotation, station lighting, touch input and flight attitude,
  travel, missions, collision, menus, and imported content.
- All 37 Python source and packaging tests passed.
- The Linux x86-64 release export launched with locally prepared content for
  120 headless frames.

## Scope and limitations

The iPhone browser and Android sensor behavior were checked through simulated
input and coordinate tests; a physical iPhone was not available for this build.
Windows, macOS, Linux ARM64, Android and Web gameplay were not run on their
target systems. Export and archive checks establish that the packages were
produced, not that those targets have been validated in play. Windows and
macOS packages are unsigned, and macOS is not notarized.

Android uses version code 34 and the existing release signing key for in-place
updates that preserve imported content and saves.
