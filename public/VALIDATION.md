# Abyssal Engine 1.2.5 — platform support

The gameplay checks ran on Linux x86-64 with Godot 4.7 and a locally imported
compatible DEEP JAR. Game content is not included in the packages.

## Validation

- All 15 engine regression suites passed headless, including gameplay,
  simulation, mission, sustained travel, STREAM transfer, terrain and UI
  coverage.
- The regression suite checks that a nearly aligned AI route remains steady,
  and that station departure discards the bank held on docking approach.
- Save round-trip and legacy-save checks cover persistent one-time hint history.
  UI checks cover the title and in-dive hint switches, loading tips, M.A.I.
  guidance and the flight control reminder.
- The danger scan is skipped at ordinary time rates, where it cannot alter the
  rate. At accelerated rates it remains part of every simulation step so nearby
  threats still stop fast travel promptly.
- All 36 Python packaging, importer and source-integrity tests passed.

## Scope and limitations

Windows, macOS, Linux ARM64 and Android gameplay were not run on their target
systems for this release. Cross-platform export and archive checks do not
establish device performance or full-game compatibility. Windows and macOS
packages are unsigned, and macOS is not notarized.

Android uses version code 29 and the existing release signing key, allowing
in-place updates that preserve imported content and saves.
