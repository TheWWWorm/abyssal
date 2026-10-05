# Abyssal Engine 1.17.5 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

All 42 Python unit tests passed on Linux x86-64. Headless Godot UI, native map/S.T.R.E.A.M. and save/session checks passed. The campaign suite passed 765 checks across all 48 chapters. All 906 engine texts and 14 translation catalogs passed their consistency and font-coverage checks.

Objective checks cover imported tutorial and counter chapters, Espionage at two of five discoveries, an independent accepted delivery during that objective, and the next chapter's actual destination after completion. The journal, chart, depth view, flight contacts and autopilot availability were checked. Russian and English imports with matching game data preserved all saved progress in both directions, including chapter, discoveries, credits, cargo and random state. Exported saves were accepted on the matching localized build too.

## Platform status

All six platform packages use Godot 4.7 release exports. Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. The browser package uses WebGL 2.

All release archives passed integrity checks and resource inventory inspection; bundled importer files were checked against their recorded hashes. The source archive matches the maintained source allowlist. The packaged Linux x86-64 executable started and exited successfully, and its shipped game pack passed title, version and mission destination checks.

The downloadable Web package was opened locally in Chromium at 1280×720. Its title rendered with version 1.17.5, with no browser warnings or errors reported during the check. Game content was not imported in that browser check.

Native Windows, macOS, Linux ARM64 and Android gameplay was not exercised for this release. Physical phones, mobile browsers and physical gamepads were not tested for this build. The source UI checks use headless rendering and do not establish device performance.

The Android application ID is org.abyssal.engine and its version code is 62. Its release signature matches the existing key, its ZIP alignment passes 16 KiB checking, and it requests no network or external-storage permission. Installing it as an update retains imported content and saves.
