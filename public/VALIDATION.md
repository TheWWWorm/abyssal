# Abyssal Engine 1.2.7 — platform support

The gameplay checks ran on Linux x86-64 with Godot 4.7 and a locally imported
compatible DEEP JAR. Game content is not included in the packages.

## Validation

- All 15 engine regression suites passed headless, including gameplay,
  simulation, mission, sustained travel, STREAM transfer, terrain, UI and the
  new imported-vessel orientation coverage.
- All 15 engine regression suites also passed with the Forward+ renderer on an
  NVIDIA RTX 3090.
- The orientation regression checks every imported bone of the eleven player
  submarines and the tanker. Each independent hull root receives one dorsal-up
  half-turn, while a non-vessel control model keeps its authored pose.
- Actual Forward+ and OpenGL Compatibility renders of all twelve vessels were
  inspected. The ship dealer and a live chase-camera flight were also captured
  from the maintained game, confirming that the cockpit, dorsal markings,
  bounds, headlights and wake agree after the correction.
- All 36 Python packaging, importer and source-integrity tests passed.

The complete OpenGL Compatibility test run is not used as a release gate on
this machine: it reaches Godot's existing 4,096 shader-instance ceiling and
reports eight headlight image assertions. The same warnings and assertions were
reproduced on an untouched 1.2.6 worktree. The changed vessel renders themselves
were inspected successfully in Compatibility mode.

## Scope and limitations

Windows, macOS, Linux ARM64 and Android gameplay were not run on their target
systems for this release. Cross-platform export and archive checks do not
establish device performance or full-game compatibility. Windows and macOS
packages are unsigned, and macOS is not notarized.

Android uses version code 31 and the existing release signing key, allowing
in-place updates that preserve imported content and saves.
