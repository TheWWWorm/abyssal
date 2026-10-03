# Abyssal Engine 1.17.1 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

Python unit tests (41) passed on Linux x86-64. Of the 23 Godot regression checks, 21 passed. Both failures are in the ocean atmosphere and ocean options checks. These failed identically on the 1.17.0 source with the same content cache and are unrelated to this release.

Save compatibility was checked with the Sony Ericsson DEEP 1.0.8 JAR and a Brazilian Portuguese translation that differs only in `data/lang/en/*.lang` and the manifest. The original JAR's import had its `music` and `water_palette` keys removed, as an import from before 1.7.0 has none. In 1.17.0, a save from the original JAR was refused on the translated import with "This save needs a matching DEEP content profile.", both with and without a stored fingerprint. In 1.17.1 both restore on the translated import, and save again and restore back on the original. The native session check covers imports without the optional keys and saves fingerprinted by 1.16.1.

## Platform status

The Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives. This release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon. Android uses the existing release signing key.

The browser package uses WebGL 2. No physical phone, mobile browser or physical gamepad was tested for this release.
