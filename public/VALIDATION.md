# Abyssal Engine 1.2.6 — platform support

The gameplay checks ran on Linux x86-64 with Godot 4.7 and a locally imported
compatible DEEP JAR. Game content is not included in the packages.

## Validation

- All 15 engine regression suites passed headless, including gameplay,
  simulation, mission, sustained travel, STREAM transfer, terrain and UI
  coverage. The UI suite covers the expedition export and import round trip.
- The Android transfer fix was verified against the Godot 4.7 source: an
  Android plugin singleton's methods are invisible to `has_method()`, while its
  signals are found by `has_signal()`, which the corrected check uses, as the
  Mods texture picker already did.
- All 36 Python packaging, importer and source-integrity tests passed.

## Scope and limitations

Windows, macOS, Linux ARM64 and Android gameplay were not run on their target
systems for this release. Cross-platform export and archive checks do not
establish device performance or full-game compatibility. The Android file
picker fix was not exercised on a device before release. Windows and macOS
packages are unsigned, and macOS is not notarized.

Android uses version code 30 and the existing release signing key, allowing
in-place updates that preserve imported content and saves.
