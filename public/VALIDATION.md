# Abyssal Engine 1.17.2 — platform support

Game content is not included. Import a compatible DEEP JAR that you supply.

## Validation

All 42 Python unit tests passed on Linux x86-64, along with the Android importer and browser audio checks. The Android bootstrap checks cover converter selection, startup failures, error reporting and transfer of converted content to the native app.

The bundled compatibility converter ran 16 decoder and class-data tests under V8 7.8. A synthetic localized JAR containing model, bitmap, MIDI and AMR resources was then converted through the Android bootstrap and importer under V8 7.8 and V8 13.6. Both produced identical decoded resource bytes and matching content identities. This checks the converter; it does not establish compatibility with every Android WebView.

The AGS3K-W09 from the player report has not been tested directly, and its active WebView version was not supplied. Physical Android validation of this fix remains pending.

## Platform status

All six platform packages were rebuilt. Their archives were checked for integrity, reviewed engine resources and bundled dependency hashes. The Android APK was signed with the existing release key, checked for 16 KiB alignment and verified to request no network permission.

The packages were not played on Windows, macOS, Linux ARM64 or Android for this release. Windows and macOS packages are unsigned; macOS is not notarized and supports Apple Silicon. The browser package uses WebGL 2. No physical phone, mobile browser or physical gamepad was tested for this release.
