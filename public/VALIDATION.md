# Abyssal Engine 1.16.1 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

Python unit tests (41) passed on Linux x86-64. Of the 23 Godot regression checks, 21 passed. Both failures are in the ocean atmosphere and ocean options checks. These failed identically on the 1.16.0 source with the same content cache and are unrelated to this release.

Save compatibility across reworded JARs was checked with the Sony Ericsson DEEP 1.0.8 JAR and a Brazilian Portuguese translation of it that differs only in `data/lang/en/*.lang` and the manifest. Both imports produce the same rules fingerprint. A save written on the original JAR without a fingerprint, as 1.16.0 writes them, restored against the translated import with the original JAR's import beside it. It was saved again under the translated JAR and restored back on the original. The native session check covers a fingerprint-only match, a refused mismatch, and text and station-name edits leaving the fingerprint unchanged. The engine UI check covers save transfer exports from reworded and foreign JARs.

## Platform status

The Windows, macOS, Linux ARM64 and Android packages were exported and checked as archives. This release was not played on those target systems. Windows and macOS packages are unsigned, and macOS is not notarized. macOS supports Apple Silicon. Android uses the existing release signing key.

The browser package uses WebGL 2. No physical phone, mobile browser or physical gamepad was tested for this release.
