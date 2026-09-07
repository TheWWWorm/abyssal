# Third-party notices

## Mascot model and animation decoder

The following files derive from the explicitly Apache-2.0-licensed files in nikita36078/J2ME-Loader, copyright 2020 Yury Kharchenko:

- `runtime/java/com/mascotcapsule/micro3d/v3/Loader.java`
- `runtime/java/com/mascotcapsule/micro3d/v3/Action.java`
- `runtime/java/com/mascotcapsule/micro3d/v3/Model.java`
- `browser/micro3d.py` - Python port of Loader/Action for browser resource conversion, with bounded parsing and JSON output.

Source commit: `9b0fa48a0a0d1e61376c0b9af28b3d2caec0a4cc`. Exact upstream URLs and hashes are recorded in `provenance/decoder-provenance.json`; they were re-fetched and verified during the 6 September 2026 review. The retained file headers and [Apache-2.0 license](licenses/Apache-2.0.txt) apply to those files and their modifications.

Modifications remove Android logging and collection dependencies, adapt the decoder to the local Java compatibility layer, and add structural validation. The rest of J2ME-Loader has not been incorporated. Licenses elsewhere in that repository must not be assumed to match these three files.

## External development and execution tools

Godot, the JDK, Python and FFmpeg are external execution/development tools. Their binaries are not included in this source package. The parent development workflow also used other tools, including a private decompiler; those are not dependencies of this edition. Standalone exports embed Godot and include `GODOT_LICENSES.txt`, generated from the actual Godot binary’s license/copyright inventory. Keep this file with the exported build. Developer source conversion uses external Python, Java and FFmpeg. Prepared desktop releases instead bundle Node.js and the portable runtimes below; no Java or FFmpeg binary is distributed.

## Original game content

DEEP and the supplied JAR, game code, text, models, textures, animation and audio are not licensed by this project. They remain the property of their respective rights holders. No game content is included in the source-only package.

## Browser importer runtime dependencies

`browser/dependencies.json` records exact upstream URLs, sizes and SHA-256 hashes. `tools/browser_runtime.py` fetches these **unmodified** runtime files into an external cache and copies them to `importer/` when exporting for Web or packaged desktop. They contain runtime/codec code, not game assets. No compiled vendor runtime is stored in this source tree.

- **Pyodide 0.28.2**, Mozilla Public License 2.0: [corresponding source at tag 0.28.2](https://github.com/pyodide/pyodide/tree/0.28.2). Keep the source link and `importer/licenses/Pyodide-MPL-2.0.txt` with every Web/desktop distribution. The runtime files are unmodified; Python engine modules remain separate files in `sources.zip`.
- **CPython 3.13.2**, PSF license and included historical/third-party notices: [corresponding source](https://github.com/python/cpython/tree/v3.13.2), `importer/licenses/CPython-3.13.2.txt`.
- **Emscripten 4.0.9** runtime support, MIT/University of Illinois NCSA and component notices: [source](https://github.com/emscripten-core/emscripten/tree/4.0.9), `importer/licenses/Emscripten-4.0.9.txt`. Exported notices also include musl/compiler-rt/libc++/libc++abi and zlib/bzip2/libffi licenses for the Python/WebAssembly runtime components.
- **opencore-amr-js**, Apache 2.0, pinned commit `dcf3d2b5f384a1d9ded2a54e4c137a81747b222b`: [corresponding codec and JavaScript wrapper source](https://github.com/yxl/opencore-amr-js/tree/dcf3d2b5f384a1d9ded2a54e4c137a81747b222b). The prebuilt `js/amrnb.js` is used unmodified; keep `importer/licenses/OpenCORE-AMR.txt` and `importer/licenses/OpenCORE-NOTICE.txt`. The upstream project includes the OpenCORE/PV codec attribution in its source headers.

`browser/audio.js` is an original procedural synthesizer. It contains no soundfont, sampled instruments or original-game music. Music bytes come only from the user's local JAR. Browser support does not resolve the separate ownership/terms questions recorded in the release review.


## Packaged desktop Node.js runtime

`desktop/dependencies.json` pins Node.js 22.23.2 for Windows/Linux x86-64 and macOS ARM64 by the official release SHA-256 inventory. `tools/desktop_runtime.py` extracts only the unmodified executable and bundled license inventory. Node is used only for local import, not for gameplay or an HTTP service. No npm installation or package download is performed on the player's computer.

Corresponding source: https://github.com/nodejs/node/tree/v22.23.2 . Official checksum source: https://nodejs.org/dist/v22.23.2/SHASUMS256.txt . The Node MIT license and included V8/OpenSSL/ICU/libuv/component notices are distributed in `importer/licenses/Node.txt` (inside app Resources on macOS). Keep that file, the pinned dependency records, and the Pyodide/codec notices with each binary distribution. Source packages contain only the independently authored importer entry point and staging code, not Node binaries.
