# Abyssal compatibility engine

Play **DEEP** as a modern desktop or browser game, using your own copy of the original.

Abyssal is a separate game engine, built in Godot, that reads a DEEP JAR you already own and converts it on your own machine. Submarine flight, stations, trading, missions and combat run natively, with modern lighting, gamepad and touch support, a readable interface and a world map with autopilot.

> **You need your own copy of DEEP.** No game data ships with this engine - no models, textures, music, sound or interface art. Nothing is downloaded for you. Without your own JAR there is nothing to play.

## Play in your browser

**[Play now at abyssal.wwworm.com](https://abyssal.wwworm.com/)** - nothing to install. Open the page, choose your own DEEP JAR, and it converts in your browser. Your JAR is never uploaded; the conversion runs entirely on your machine and the converted content stays in your browser's local storage.

Needs WebGL 2 and a desktop-class browser. For the smoothest experience, and to keep your imported content across browsers, use a desktop package below.

## Download and play

**[Download the latest release →](https://github.com/TheWWWorm/abyssal/releases/latest)**

| Platform | Download | Start |
| --- | --- | --- |
| Windows x86-64 | `…-windows.zip` | `abyssal.exe` |
| Linux x86-64 | `…-linux.tar.gz` | `AbyssalEngine/abyssal.x86_64` |
| macOS Apple Silicon | `…-macos.zip` | `abyssal.app` |
| Browser (WebGL 2) | `…-web.zip` | Host the archive yourself, or [use the hosted build](https://abyssal.wwworm.com/) |

Extract the **entire** archive and keep the files together. You do not need Godot, Python, Java, Node.js or a compiler - the desktop packages carry everything they need, and conversion runs completely offline.

1. Launch the application.
2. Choose your DEEP JAR when asked. Its filename does not matter.
3. Wait for the first conversion to finish before closing the app.

Your JAR never leaves your computer. The game remembers imported content and station checkpoints in your user storage, so you only import once.

### Which DEEP builds work

The engine is developed against the **Sony Ericsson release of DEEP 1.0.8**, identified by SHA-256:

`a247f8a872dda268ed8138086bd0de6d038d7faf7ef31469b0efe3eb54209d26`

That is the build all gameplay checking is done on. It is not a requirement. Any DEEP MIDlet JAR is accepted, and the importer converts it whenever the build stores its data the way the engine expects. Localised builds are supported: the language shipped in the JAR is the language you play in.

Builds that have actually been run through the importer:

| Build | Result |
| --- | --- |
| Sony Ericsson 1.0.8 (English) | Developed and validated against this build |
| Sony Ericsson 1.0.3 (Russian) | Converts; the engine check suite passes on it, and the game is in Russian |
| Nokia 1.0.3 | Does not convert; its code differs in ways the restricted data reader does not cover |

If a build does not match, import stops with a message naming what did not fit, rather than producing a broken game.

## Before you download - please read

- **Windows and macOS have never been run on their native systems.** They are built and packaged, but not tested on real hardware. Both are unsigned and macOS is not notarized, so those systems may warn about or block them.
- **macOS is Apple Silicon only.** Intel Macs cannot run this build.
- **Linux** is the only platform where gameplay has been rendered and visually checked.
- **The browser build needs a web host.** Opening `index.html` from your disk will not work.
- **Android** is not a player release. There is a developer target that accepts prepared content packs only.

## Controls

| Action | Keyboard / mouse | Gamepad (Xbox labels) | Touch |
| --- | --- | --- | --- |
| Steer | Mouse, Up / Down pitch | Right stick, or the left stick when set to turn | Left thumb stick, or drag any free area |
| Strafe left / right | A / D | Left stick (analog) | Left thumb stick, which turns by default |
| Throttle | W / S | D-pad up / down | Hold + SPEED / − SPEED |
| Guns / harpoon | Left / right mouse | RT / LT | Hold GUNS / HOOK |
| Selected weapon / bank | Space / Tab | A / X | GUNS or HOOK / BANK |
| Boost | Shift | Left stick click (L3) | Hold BOOST |
| Dock / STREAM gate | E | Y | DOCK |
| World map / autopilot | M / R (hold R for objective) | View (Back) / LB | MAP / ROUTE |
| Time: 1×/2×, autopilot to 16× | T | RB | TIME |
| Camera / lights | C / L | D-pad left / right | VIEW / Graphics menu |
| Pause / back | Escape | Start / B | MENU / Back |
| Menus | Arrows / Enter | D-pad or stick / A | Tap |
| Auto fire / fullscreen | Q / F11 | - | Hold weapon / FULL |

**Controls** in the options menu offers keyboard remapping, mouse sensitivity and inversion, controller deadzone and inversion, touch look sensitivity, Touch **Auto / On / Off**, and left/right handling as **Auto / Always strafe / Always turn**. Only the most recently used controller owns flight. The game pauses if a controller disconnects or the window loses focus.

A and D, and the gamepad left stick, slide the submarine sideways rather than turning it. Turning is the mouse, or the right stick. On a touchscreen the thumb stick keeps turning instead, because a thumb has nothing else to turn with. **Left/right keys and stick** in the Controls menu overrides that choice on any platform. Lateral thrust runs at a fraction of cruise speed and ignores the throttle, so a stopped submarine can still slide out of trouble, and it counts as manual control: strafing disengages an autopilot course.

Lists and menus scroll by dragging anywhere inside them, not only on the narrow scroll bar. A short tap still selects the row under your finger; once the finger has clearly moved the gesture becomes a scroll and the row is not activated. The atlas keeps its own pan and pinch.

On a touchscreen the stick is not fixed in place: it appears wherever your left thumb lands and returns to its resting corner when you lift off. Dragging any free area of the screen steers as the mouse does, so you can hold the stick with one thumb and aim with the other. FULL puts the game fullscreen. iPhone browsers expose no fullscreen control at all, so there the game points you to the Share menu and Add to Home Screen; launching from that icon runs it without browser bars. Where a browser does offer fullscreen, FULL uses it, and the button is dropped once the game is already running without browser chrome.

On the world map, tap a station, drag to pan and pinch to zoom. With a mouse, right-drag and scroll. Controller users can navigate a searchable station list without pointing at the map.

## Playing

The dock keeps the original Hangar, Missions, Map, Trade, Status and System grouping, and shows each station's ownership and tech level. Hangar holds the equipment shop, ship dealer and workshop; Status holds your ship, cargo and pilot record. Station names stay visible in flight, and quest destinations get gold labels and off-screen direction markers.

Map search offers continuous autopilot or a STREAM transfer. Time acceleration runs ordinary simulation ticks - T cycles 1×/2× in manual flight and up to 16× during clear autopilot travel, dropping back to 1× near danger or on arrival. Autopilot passes stations vertically within your ship's pressure limits.

Encounters come from reusable mission types with generated formations and routes. Colonist stations buy all remaining cargo at fixed catalog prices once deliveries due there are complete, and the dock keeps an explicit sale receipt. Other stations keep your cargo for manual trading and crafting.

Classic instruments work with either classic or enhanced lighting, and both use the original models and textures. Modern lighting derives hull relief, roughness and warm window masks from your own imported textures at runtime; the source textures and silhouettes are preserved. Station textures stay pixelated by default - turn on **Station texture smoothing** in Graphics if you prefer filtered surfaces.

Campaign and radio content comes from your local JAR. Exact choreography, timings and balance can differ from the original. Existing engine saves migrate to the native RNG, so future random outcomes may change.

## Browser version

Extract the whole Web ZIP to an HTTPS host, keeping `importer/` and the notices in place. JAR hashing needs a secure context, so use HTTPS (`localhost` also qualifies). The export includes a `_headers` file, so any static host that reads it serves WebAssembly as `application/wasm` and caches content-hashed game packs correctly without extra configuration.

### Publish it on Cloudflare

`public/` holds a ready-to-serve copy of the exported Web build and `wrangler.toml` describes it, so Cloudflare deploys straight from this repository with no build step of its own:

1. In the Cloudflare dashboard, create a Worker and connect it to this repository.
2. Leave the build command empty. `npx wrangler deploy` reads `wrangler.toml` and uploads `public/` as static assets.
3. If your Worker uses a different name, change `name` in `wrangler.toml` to match.

Cloudflare rejects any asset over 25 MiB, and the Godot engine binary is about 38 MiB. `tools/prepare_web_host.py` splits oversized files into numbered parts, and `worker.js` streams them back together under the original path. The parts stay uncompressed on purpose: Cloudflare negotiates its own `Content-Encoding` for the response and strips one set by the Worker, so pre-compressed bytes would reach the browser undecoded. The release archives keep whole files, so they stay portable to hosts with no size limit.

To refresh the hosted build after a new export:

```sh
python3 tools/export_game.py --platform web --release --output /outside/repo/builds/web
python3 tools/prepare_web_host.py --source /outside/repo/builds/web --output public
git add -A && git commit -m "Web build" && git push
```

Browser saves and content live in IndexedDB for that exact origin. Changing the port or hostname creates separate storage, and clearing site data, private browsing or storage eviction can lose it. **Keep your JAR** so you can reinstall. Cloud sync and save transfer between platforms are not implemented. Low-memory browsers may need a prepared content pack instead of live conversion.

The first import loads roughly 12 MiB of extra runtime files; later launches read the installed content.

## Project status

This is a **development preview**, and its public release provenance is unresolved.

The importer checks your JAR against the supported SHA-256, then decodes its resource entries and reads class-file data tables with a **restricted bytecode evaluator**. That evaluator reads literal assignments, arrays, arithmetic and bounded control flow, resolving calls only through explicit inert data summaries; unsupported opcodes fail. It never loads or invokes original classes in a JVM, and no original bytecode or method body is written to its output.

It does, however, inspect and evaluate parts of original method bodies. Because some content is derived that way, this is reverse engineering and **not** a clean-room reimplementation. Decoded models, textures, audio, catalogue rows and narrative records exist only in your own local cache - none are distributed here.

This engine's own source is licensed under the [Apache License 2.0](LICENSE.md). That covers the code in this repository and nothing else. It grants you no rights to the original DEEP game, its JAR, its class files or anything converted from them; those are not this project's to license and are not distributed here. The three vendored decoder files keep their own Apache-2.0 notices, listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Content you convert is private. Do not redistribute it with the engine, and never share the JAR, a converted pack or a conversion cache.

The name is a working title, not a trademark claim. Menus and instrument frames are drawn in code; original logos, portraits and icons are loaded locally from your own import.

## For developers

Requires Godot **4.7 Standard** with matching export templates, and Python 3.10+. Run everything from the repository root and keep builds and game content outside it.

```sh
# All player archives, including the offline desktop importers:
python3 tools/package_releases.py --version 0.1.0-preview.2 --output /outside/repo/releases/0.1.0-preview.2
# A single unpackaged export (windows, linux, macos, web, android):
python3 tools/export_game.py --platform linux --release --output /outside/repo/builds/linux
```

Builds fetch and verify pinned runtimes once into an external cache (`~/.cache/abyssal-engine` on Linux, `~/Library/Caches/abyssal-engine` on macOS, `%LOCALAPPDATA%/abyssal-engine` on Windows; override with `ABYSSAL_CACHE_HOME`). No JAR is needed to build. Pass `--godot /path/to/godot` or set `GODOT_PATH` if it is not on your PATH.

To run from source with direct JAR conversion you also need JDK 17+ and FFmpeg:

```sh
python3 tools/run.py --jar /private/path/deep3d.jar --compatibility
python3 tools/serve_web.py --directory /outside/repo/builds/web --port 8060   # local web testing
```

Checks and packaging:

```sh
python3 tools/check.py --cache '/path/printed/by/import' --godot '/path/to/godot'
python3 -m unittest discover -s tests -p 'test_*.py'
python3 tools/audit_provenance.py
```

Packaging reads the explicit allowlist in `source-manifest.json`, checks that the Java bridge stays clear of the original game's class loading, and rejects unexpected files, symlinks and disguised binaries. A per-file review record is kept with the working tree and is not distributed. None of this infers legal ownership.

Prepared archives are attached to [releases](https://github.com/TheWWWorm/abyssal/releases) rather than committed, which keeps this repository small.

See also [third-party notices](THIRD_PARTY_NOTICES.md) and [license status](LICENSE.md). Each release carries its own `VALIDATION.md` recording what was actually executed for that build.

## Donations
If you want to support this development or ones similar to it, you can do it here https://ko-fi.com/wwworm
Please only do it if you have money for it and always be financially responsibe. Nevertheless I am grateful for any support given. 
