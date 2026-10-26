# Third-party notices

## Mascot model and animation decoder

The following files derive from the explicitly Apache-2.0-licensed files in nikita36078/J2ME-Loader, copyright 2020 Yury Kharchenko:

- `runtime/java/com/mascotcapsule/micro3d/v3/Loader.java`
- `runtime/java/com/mascotcapsule/micro3d/v3/Action.java`
- `runtime/java/com/mascotcapsule/micro3d/v3/Model.java`
- `browser/micro3d.py` - Python port of Loader/Action for browser resource conversion, with bounded parsing and JSON output.

Source commit: `9b0fa48a0a0d1e61376c0b9af28b3d2caec0a4cc`. Exact upstream URLs and hashes are recorded in `provenance/decoder-provenance.json`; they were re-fetched and verified during the 6 September 2026 review. The retained file headers and [Apache-2.0 license](licenses/Apache-2.0.txt) apply to those files and their modifications.

Modifications remove Android logging and collection dependencies, adapt the decoder to the local Java compatibility layer, and add structural validation. The rest of J2ME-Loader has not been incorporated. Licenses elsewhere in that repository must not be assumed to match these three files.

## Interface fonts for Chinese, Japanese and Korean

`game/native/locale/noto_sans_sc.otf`, `noto_sans_jp.otf` and `noto_sans_kr.otf` are subsets of **Noto Sans CJK** (Regular, version 2.004, SC, JP and KR faces), copyright 2014-2021 Adobe, with Reserved Font Name 'Source', licensed under the [SIL Open Font License 1.1](licenses/OFL-1.1.txt). Each subset holds only the characters the matching engine text catalog uses; `tools/engine_text.py fonts` writes them from the unmodified upstream collection. Source: https://github.com/notofonts/noto-cjk . Keep the license with every distribution that includes these files.

## External development and execution tools

Godot, the JDK, Python and FFmpeg are external execution/development tools. Their binaries are not included in this source package. The parent development workflow also used other tools, including a private decompiler; those are not dependencies of this edition. Standalone exports embed Godot and include `GODOT_LICENSES.txt`, generated from the actual Godot binary’s license/copyright inventory. Keep this file with the exported build. Developer source conversion uses external Python, Java and FFmpeg. Prepared desktop releases instead bundle Node.js and the portable runtimes below; no Java or FFmpeg binary is distributed.

`engine/godot-4.7/station-rendering.patch` modifies Godot's rendering code. The Godot source context in the patch retains Godot's MIT license and attribution; a custom runtime remains subject to the same Godot license inventory as an official export. The patch includes no game assets or converted content.

## Original game content

DEEP and the supplied JAR, game code, text, models, textures, animation and audio are not licensed by this project. They remain the property of their respective rights holders. No game content is included in the source-only package.

## Engine weapon launch sounds

`game/audio/weapons/` contains 48 composite game effects, with three variations per weapon, adapted from these recordings:

- **RescopicSound**, Pulse TM, Pulse DN, Plasma KU and Plasma PP weapon designs, via [Pixabay](https://pixabay.com/sound-effects/film-special-effects-sci-fi-weapon-shoot-firing-pulse-tm-01-233821/).
- **DRAGON-STUDIO**, [Gentle Underwater Swish](https://pixabay.com/sound-effects/film-special-effects-gentle-underwater-swish-499658/), via Pixabay.
- **ejah_music**, [Underwater whoosh (Deep)](https://pixabay.com/sound-effects/underwater-whoosh-deep-464534/), via Pixabay.
- **felix.blume**, [Underwater recording of aquatic movement, bubbles and drops](https://freesound.org/people/felix.blume/sounds/384218/), under CC0 1.0.

Attribution is optional under the [Pixabay Content License](https://pixabay.com/service/terms/#license) and [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/); these credits are provided voluntarily. Each source title, contributor page, download URL and SHA-256 hash is recorded in `provenance/weapon-audio.json`.

The effects combine recordings, frequency bands, timing and envelopes into equipment-specific discharges. These adapted effects retain the [Pixabay Content License](licenses/Pixabay-Content-License.txt); they are not CC0 or Apache-2.0. The hydrophone component remains [CC0 1.0](licenses/CC0-1.0.txt). Source MP3 quality is preserved, not described as lossless. Original source recordings are not bundled. Output hashes and preparation are in `provenance/weapon-audio.json` and `tools/build_weapon_audio.py`. Original harpoon sounds still come from the supplied compatible DEEP JAR.

## Browser importer runtime dependencies

`browser/dependencies.json` records exact upstream URLs, sizes and SHA-256 hashes. `tools/browser_runtime.py` fetches these **unmodified** runtime files into an external cache and copies them to `importer/` when exporting for Web, packaged desktop or Android. They contain runtime/codec code, not game assets. No compiled vendor runtime is stored in this source tree.

- **Pyodide 0.28.2**, Mozilla Public License 2.0: [corresponding source at tag 0.28.2](https://github.com/pyodide/pyodide/tree/0.28.2). Keep the source link and `importer/licenses/Pyodide-MPL-2.0.txt` with every Web/desktop/Android distribution. The runtime files are unmodified; Python engine modules remain separate files in `sources.zip`.
- **CPython 3.13.2**, PSF license and included historical/third-party notices: [corresponding source](https://github.com/python/cpython/tree/v3.13.2), `importer/licenses/CPython-3.13.2.txt`.
- **Emscripten 4.0.9** runtime support, MIT/University of Illinois NCSA and component notices: [source](https://github.com/emscripten-core/emscripten/tree/4.0.9), `importer/licenses/Emscripten-4.0.9.txt`. Exported notices also include musl/compiler-rt/libc++/libc++abi and zlib/bzip2/libffi licenses for the Python/WebAssembly runtime components.
- **opencore-amr-js**, Apache 2.0, pinned commit `dcf3d2b5f384a1d9ded2a54e4c137a81747b222b`: [corresponding codec and JavaScript wrapper source](https://github.com/yxl/opencore-amr-js/tree/dcf3d2b5f384a1d9ded2a54e4c137a81747b222b). The prebuilt `js/amrnb.js` is used unmodified; keep `importer/licenses/OpenCORE-AMR.txt` and `importer/licenses/OpenCORE-NOTICE.txt`. The upstream project includes the OpenCORE/PV codec attribution in its source headers.

`browser/audio.js` is an original procedural synthesizer. It contains no soundfont, sampled instruments or original-game music. Music bytes come only from the user's local JAR. Browser support does not resolve the separate ownership/terms questions recorded in the release review.


## NVIDIA Streamline (Windows package only)

`engine/godot-4.7/nvidia-dlss.patch` ports the Streamline, DLSS and frame-generation integration from NVIDIA's Godot fork (https://github.com/NVIDIA-RTX/godot, MIT, Copyright (c) 2014-present Godot Engine contributors; Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur) to Godot 4.7. Building with it compiles in the MIT-licensed Streamline SDK headers, which `tools/prepare_streamline.py` fetches and checks. Only the Windows package distributes NVIDIA's unmodified production runtime from Streamline 2.14.16 (`sl.*.dll`, `nvngx_dlss.dll`, `nvngx_dlssg.dll`), under NVIDIA's license terms, which it carries in `licenses/nvidia-streamline/`. Its splash screen and About page show NVIDIA's GeForce RTX badge, which is NVIDIA's artwork and not part of the source archive. This software contains source code provided by NVIDIA Corporation. NVIDIA, the NVIDIA logo, GeForce RTX, DLSS and Reflex are trademarks and/or registered trademarks of NVIDIA Corporation in the U.S. and other countries. Other packages and source archives contain no NVIDIA runtime files or artwork.

## AMD FidelityFX SDK and DirectX Agility SDK (Windows package only)

`engine/godot-4.7/amd-fsr.patch` and `amd-fsr-after-nvidia-dlss.patch` add a Direct3D 12 integration of AMD's FidelityFX SDK 2.3.0 (FSR 3.1 and FSR 4 upscaling and frame generation) to Godot 4.7. Building with either compiles in the SDK's MIT-licensed API headers (Copyright (c) Advanced Micro Devices, Inc.), which `tools/prepare_fsr_sdk.py` fetches and checks. Only the Windows package distributes AMD's unmodified signed runtime (`amd_fidelityfx_loader_dx12.dll`, `amd_fidelityfx_upscaler_dx12.dll`, `amd_fidelityfx_framegeneration_dx12.dll`) under the SDK's license, which it carries with AMD's third-party notices in `licenses/amd-fidelityfx/`. It also includes Microsoft's DirectX Agility SDK 1.618.5 runtime (`x86_64/D3D12Core.dll`) under its license terms in `licenses/microsoft-directx-agility/`. Other packages and source archives contain no AMD or Microsoft runtime files.

## AMD FSR artwork

`game/ui/vendors/` holds AMD's official white AMD FSR Upscaling and AMD FSR Frame Generation lockups, unmodified, from AMD's [FSR naming and branding guidelines](https://gpuopen.com/amd-fsr-naming-guidelines/); their download addresses and SHA-256 hashes are in `game/ui/vendors/NOTICE.md`. Only the package that bundles the AMD FidelityFX SDK shows them, on the splash screen and in About. AMD, the AMD Arrow logo, AMD FSR and combinations thereof are trademarks of Advanced Micro Devices, Inc. The artwork is not covered by this project's Apache-2.0 license.

## Packaged desktop Node.js runtime

`desktop/dependencies.json` pins Node.js 22.23.2 for Windows/Linux x86-64 and macOS ARM64 by the official release SHA-256 inventory. `tools/desktop_runtime.py` extracts only the unmodified executable and bundled license inventory. Node is used only for local import, not for gameplay or an HTTP service. No npm installation or package download is performed on the player's computer.

Corresponding source: https://github.com/nodejs/node/tree/v22.23.2 . Official checksum source: https://nodejs.org/dist/v22.23.2/SHASUMS256.txt . The Node MIT license and included V8/OpenSSL/ICU/libuv/component notices are distributed in `importer/licenses/Node.txt` (inside app Resources on macOS). Keep that file, the pinned dependency records, and the Pyodide/codec notices with each binary distribution. Source packages contain only the independently authored importer entry point, Discord IPC helper and staging code, not Node binaries. The optional Discord Rich Presence helper reuses this runtime and includes no Discord SDK or additional library.

Android packages keep the importer, pinned dependency record and all importer licenses under `assets/abyssal-importer/` in the APK, alongside the Godot license inventory and this notice. Android System WebView is provided by the device, not distributed by this project. The Android Java bridge uses the platform and Godot APIs; it includes no GoF game code or content.

## Android compatibility converter

`android/dependencies.json` pins a second, unmodified offline runtime for older Android WebViews. The APK automatically selects it when the primary converter's JavaScript or WebAssembly features are unavailable. It runs the same separate Python decoder modules from `sources.zip`; no original game assets or runtime are included. The files live under `assets/abyssal-importer/vendor-compat/` and use the same external build cache and checksum verification as the primary runtime.

- **Pyodide 0.20.0**, Mozilla Public License 2.0: [corresponding source](https://github.com/pyodide/pyodide/tree/0.20.0), `licenses/Pyodide-0.20.0-MPL-2.0.txt` inside the importer. The JavaScript retains its included Microsoft TypeScript helper notice.
- **CPython 3.10.2**, PSF license and historical/component notices: [corresponding source](https://github.com/python/cpython/tree/v3.10.2), `licenses/CPython-3.10.2.txt`.
- **Emscripten 2.0.27** runtime support, MIT/University of Illinois NCSA and component notices: [corresponding source](https://github.com/emscripten-core/emscripten/tree/2.0.27), `licenses/Emscripten-2.0.27.txt`, with matching musl/compiler-rt/libc++ notices. Keep these additional licenses and the pinned Android dependency record with every APK.
- The compatibility runtime also includes **FreeType**, distributed under the FreeType License, from Emscripten's [version_1 port](https://github.com/emscripten-ports/FreeType/tree/version_1), **libpng 1.6.37** under the PNG Reference Library License ([source](https://github.com/pnggroup/libpng/tree/v1.6.37)), and **libffi 3.3** under its MIT-style license ([source](https://github.com/libffi/libffi/tree/v3.3)). Their notices are included as `licenses/FreeType-compat-LICENSE.txt`, `licenses/FreeType-compat-FTL.txt`, `licenses/libpng-1.6.37.txt` and `licenses/libffi-3.3.txt`.

## Optional texture reconstruction

The fitted vector and material recipe in `game/native/textures/reconstruction_recipe.json` derives from the v6 restoration artwork. It contains artwork-derived geometry and shading parameters, with no original or generated bitmap files. Original DEEP artwork and derivatives are not licensed by this project’s Apache-2.0 code license. See [texture reconstruction provenance](provenance/texture-reconstruction.md).
