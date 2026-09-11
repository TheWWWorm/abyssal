# Platform support — 0.1.0-preview.5

Packages contain the engine and offline importer only. A supplied compatible DEEP JAR is required; original game assets and converted content are not included.

This release fixes station texture smoothing in classic lighting, preserves station streaming state when filtering changes, and adds an optional whole-screen touch look area.

- Linux: automated platform input (118 checks), gamepad UI (53 checks), engine UI, and readability checks pass in desktop Godot. NVIDIA OpenGL Compatibility rendering checks pass, including image-based station filtering checks in classic and enhanced lighting. Repeated toggles retain current and distant station models, cached geometry and fade state. Touch checks cover equal drag movement in both screen areas, simultaneous weapons/throttle, cancellation and returning to the floating stick. Controller and touch events were injected; no physical controller was used.
- Android: rebuilt signed release APK for ARM64 and x86-64, Android 8 or newer, OpenGL ES 3. It retains the application ID and signing key, with version code 5. This update has not been exercised on physical Android hardware or in an Android emulator; input behavior was tested in desktop Godot.
- Previous Android validation (preview.3): prepared `.abyss` pack installation, native gameplay, touch steering, Android Back, and installed-content/save persistence passed in an Android 15 x86-64 emulator. A player reported successful gameplay and direct JAR import on physical Retroid Pocket 5 hardware with preview.3. Audio output was not separately assessed.
- Android direct JAR import: the previous emulator's Android System WebView 128 stopped before decoder startup. Prepared-pack import remains the fallback on affected devices. The importer is unchanged in this update. Keep Android System WebView enabled and current for direct JAR import.
- Windows x86-64 and macOS Apple Silicon: rebuilt packages; no execution on native hardware. Windows/macOS binaries are unsigned; macOS is not notarized.
- Browser: rebuilt Web export includes the pinned importer and a content-hashed game pack. Host the complete archive over HTTPS or localhost. This update has not been exercised in a browser.

SHA256SUMS and release.json identify the downloadable files. Third-party license inventories are included in each distribution; Android keeps them inside APK assets/abyssal-importer/. These checks do not establish full-game fidelity or physical-device performance.
