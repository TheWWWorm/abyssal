#!/usr/bin/env python3
"""Assemble one reviewed source-and-release folder, or verify an existing one.

This checks distribution contents and integrity, not legal rights or ownership.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import struct
import tarfile
import tempfile
import zipfile

from paths import ROOT
from package_source import source_files

PRIVATE = {'.jar', '.class', '.abyss', '.mbac', '.mtra', '.amr', '.mid',
           '.midi', '.ogg', '.wav', '.glb', '.gltf', '.blend', '.keystore'}
PRIVATE_DIRS = {'reference', 'captures', 'content', '.local', '.git', '__pycache__'}
MANIFEST = 'publication-manifest.json'


def digest(path):
    with path.open('rb') as stream:
        result = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
        return result.hexdigest()


def safe_name(name):
    path = PurePosixPath(name)
    if not name or path.is_absolute() or '..' in path.parts or '\\' in name or ':' in name:
        raise ValueError('Unsafe archive path: ' + name)
    if path.suffix.lower() in PRIVATE or PRIVATE_DIRS.intersection(path.parts):
        raise ValueError('Private content path: ' + name)


def pck_entries(data, source_names):
    """Inspect standalone Godot 4.7 pack directories without running the game.

    Format reference: Godot 4.7 core/io/file_access_pack.cpp (upstream MIT).
    Only unencrypted standalone v3/v4 exports are accepted, failing closed.
    """
    if len(data) < 40 or data[:4] != b'GDPC':
        raise ValueError('Invalid standalone game pack')
    version, = struct.unpack_from('<I', data, 4)
    flags, = struct.unpack_from('<I', data, 20)
    if version not in {3, 4} or flags != 2:
        raise ValueError('Unsupported/encrypted game pack')
    base, cursor = struct.unpack_from('<QQ', data, 24)
    count, = struct.unpack_from('<I', data, cursor)
    cursor += 4
    if not 1 <= count <= 10000:
        raise ValueError('Unexpected game pack entry count')
    names = []
    for _ in range(count):
        length, = struct.unpack_from('<I', data, cursor)
        cursor += 4
        if length > 4096 or cursor + length + 36 > len(data):
            raise ValueError('Invalid game pack directory entry')
        name = data[cursor:cursor + length].rstrip(b'\0').decode('utf-8')
        cursor += length
        offset, size = struct.unpack_from('<QQ', data, cursor)
        entry_flags, = struct.unpack_from('<I', data, cursor + 32)
        cursor += 36
        safe_name(name)
        if entry_flags or base + offset + size > len(data):
            raise ValueError('Invalid/encrypted game pack payload: ' + name)
        source = name[:-6] if name.endswith('.remap') else name
        if source.endswith('.gdc'):
            source = source[:-1]
        generated = name in {'project.binary', '.godot/global_script_class_cache.cfg', '.godot/uid_cache.bin'}
        scene = re.fullmatch(r'\.godot/exported/\d+/export-[a-f0-9]+-native_main\.scn', name)
        if not generated and not scene and 'game/' + source not in source_names:
            raise ValueError('Unreviewed resource in game pack: ' + name)
        names.append(name)
    if len(names) != len(set(names)):
        raise ValueError('Duplicate game pack entry')
    return len(names)


def inspect_zip(data, source_names, depth=0):
    if depth > 3:
        raise ValueError('Unexpected nested archive depth')
    count = 0
    packs = []
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        seen = set()
        for info in archive.infolist():
            safe_name(info.filename)
            if info.filename in seen or stat.S_ISLNK(info.external_attr >> 16):
                raise ValueError('Duplicate entry or link: ' + info.filename)
            seen.add(info.filename)
            if info.is_dir():
                continue
            payload = archive.read(info)  # also checks CRC
            count += 1
            if info.filename.endswith('.zip'):
                nested, nested_packs = inspect_zip(payload, source_names, depth + 1)
                count += nested
                packs.extend(nested_packs)
            elif info.filename.endswith('.pck'):
                packs.append(pck_entries(payload, source_names))
    return count, packs


def inspect_archive(path, source_names):
    if path.suffix == '.zip':
        count, packs = inspect_zip(path.read_bytes(), source_names)
    else:
        count, packs, seen = 0, [], set()
        with tarfile.open(path, 'r:gz') as archive:
            for member in archive:
                safe_name(member.name)
                if member.name in seen or not (member.isfile() or member.isdir()):
                    raise ValueError('Duplicate entry or special file: ' + member.name)
                seen.add(member.name)
                if member.isdir():
                    continue
                payload = archive.extractfile(member).read()
                count += 1
                if member.name.endswith('.zip'):
                    nested, nested_packs = inspect_zip(payload, source_names)
                    count += nested
                    packs.extend(nested_packs)
                elif member.name.endswith('.pck'):
                    packs.append(pck_entries(payload, source_names))
    return {'file': path.name, 'archive_entries_including_nested': count, 'game_pack_entry_counts': packs}


def release_files(folder, source_names):
    metadata = json.loads((folder / 'release.json').read_text())
    version = metadata['version']
    if not re.fullmatch(r'[0-9][A-Za-z0-9.-]{0,60}', version):
        raise ValueError('Invalid release version')
    records = [*metadata['artifacts'], metadata['source']]
    expected = {'README.md', 'SHA256SUMS', 'VALIDATION.md', 'release.json'}
    checksums = {}
    for line in (folder / 'SHA256SUMS').read_text().splitlines():
        value, name = line.split('  ', 1)
        if name in checksums:
            raise ValueError('Duplicate release checksum')
        checksums[name] = value
    reports = []
    for record in records:
        name = record['file']
        safe_name(name)
        if '/' in name or name in expected:
            raise ValueError('Duplicate/nested release filename')
        expected.add(name)
        path = folder / name
        if path.is_symlink() or path.stat().st_size != record['bytes'] or digest(path) != record['sha256']:
            raise ValueError('Release checksum mismatch: ' + name)
        if checksums.get(name) != record['sha256']:
            raise ValueError('Release checksum inventory mismatch: ' + name)
        reports.append(inspect_archive(path, source_names))
    if set(checksums) != {record['file'] for record in records}:
        raise ValueError('Unexpected release checksums')
    if {p.name for p in folder.iterdir()} != expected or any(p.is_symlink() for p in folder.iterdir()):
        raise ValueError('Unexpected files in release folder')
    return version, sorted(expected), reports


def inventory(folder):
    result = {}
    for path in sorted(folder.rglob('*')):
        if path.relative_to(folder).parts[0] == '.git':
            continue  # Version-control metadata is not distribution content.
        if path.is_symlink():
            raise ValueError('Symbolic link in publication folder: ' + str(path))
        if path.is_file() and path != folder / MANIFEST:
            name = path.relative_to(folder).as_posix()
            safe_name(name)
            result[name] = digest(path)
    return result


def verify(folder):
    folder = Path(folder).resolve()
    record = json.loads((folder / MANIFEST).read_text())
    if inventory(folder) != record['files']:
        raise ValueError('Publication inventory changed: missing, modified or extra files')
    source_names = set(json.loads((folder / 'engine/source-manifest.json').read_text())['files'])
    version, _, reports = release_files(folder / 'releases' / record['version'], source_names)
    if reports != record['archive_inspection']:
        raise ValueError('Archive inspection differs from recorded publication')
    return {'version': version, 'files': len(record['files']), 'archives': len(reports),
            'integrity': 'passed', 'legal_clearance': False}


def assemble(release, output):
    release, output = Path(release).resolve(), Path(output).absolute()
    if output.exists() or output.is_relative_to(ROOT) or output.is_relative_to(release):
        raise ValueError('Use a new output folder outside source and release inputs')
    sources = source_files()
    source_names = {p.relative_to(ROOT).as_posix() for p in sources}
    version, names, reports = release_files(release, source_names)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.publication-', dir=output.parent) as temp:
        stage = Path(temp) / 'publish'
        stage.mkdir()
        for source in sources:
            target = stage / 'engine' / source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        target_release = stage / 'releases' / version
        target_release.mkdir(parents=True)
        for name in names:
            shutil.copyfile(release / name, target_release / name)
        (stage / 'README.md').write_text(f'''# Abyssal Engine — publication bundle

This is the single distribution root. It contains the reviewed engine source and the prepared {version} releases. Copy this folder as a whole; the development workspace outside it is not part of the distribution.

## Play

[Download a prepared Windows, Linux or macOS package](releases/{version}/README.md), extract the complete archive and launch its executable/app. Select your own DEEP JAR. Players do not install build tools. A Web hosting package is included too. See the [engine README](engine/README.md) and [actual validation results](releases/{version}/VALIDATION.md).

## Contents

- `engine/`: self-contained reviewed source, build tools, tests and documentation.
- `releases/{version}/`: checksums, validation record and release notes for the latest prepared player packages. The archives themselves are published as release assets rather than committed; download them into this folder to reassemble the complete distribution. No old previews are included.
- `publication-manifest.json`: exact file hashes and inspection results, including nested ZIPs and Godot game-pack directories.

The engine source also includes publication tooling added after the preview build. The release source ZIP records the source used for that preview; no gameplay changes are implied by assembling this folder.

No original JAR, original game class files, extracted graphics/audio, imported content packs, saves, screenshots, decompiled reference tree, obsolete phone runtime, development caches or private tools are included. Vendor runtimes and their required notices are included inside player packages so they can launch without installing development tools.

## Source and attribution

Start with [engine/README.md](engine/README.md). The optional Java developer converter contains the attributed Apache-2.0 resource decoder and local conversion utilities, not the removed original-game class-loading runtime. The portable player importer uses Python in WebAssembly with JavaScript orchestration. Preserve [third-party notices](engine/THIRD_PARTY_NOTICES.md) and the bundled license texts.

**The engine source is licensed under Apache-2.0; the original game and anything converted from it are not.** This folder is a technically audited publication candidate, not a legal clearance for the original material. [License](engine/LICENSE.md) and the decoder review in `engine/provenance/` remain part of the bundle. Windows/macOS previews are unsigned and have not been executed on their native systems.

## Verify before distributing

From this folder, using Python 3.10+ (maintainers only):

```sh
python3 -B engine/tools/package_publication.py --verify .
```

Download the release archives into `releases/{version}/` first; they are distributed as release assets, so a fresh clone does not contain them and the check reports them as missing. The check rejects extra or changed files, altered archives and private content paths. It inspects nested converter archives and permits only reviewed engine resources in Godot packs. It does not determine copyright ownership. After intentional source changes, run the source checks and assemble a new bundle; do not hand-edit the recorded hashes to hide added files.
''')
        (stage / '.gitignore').write_text('''# Private content and generated files must stay outside this distribution.
**/.godot/
**/__pycache__/
*.jar
*.class
*.abyss
*.partial
*.keystore
**/content/
**/reference/
**/captures/
.DS_Store
Thumbs.db
# Prepared player archives are published as release assets, not committed.
releases/**/*.zip
releases/**/*.tar.gz
''')
        (stage / 'LICENSE.md').write_text('# License\n\nThe engine source is licensed under the Apache License 2.0; see [engine/LICENSE.md](engine/LICENSE.md) and [third-party notices](engine/THIRD_PARTY_NOTICES.md). The original game and any content converted from it are not licensed by this project and are not included here. Packaging does not change ownership or licensing.\n')
        record = {'schema': 1, 'version': version, 'legal_clearance': False,
                  'files': inventory(stage), 'archive_inspection': reports}
        (stage / MANIFEST).write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
        result = verify(stage)
        stage.rename(output)
    return {'folder': str(output), **result}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', type=Path)
    parser.add_argument('--release-dir', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.verify:
        if args.release_dir or args.output:
            parser.error('--verify cannot be combined with assembly arguments')
        print(json.dumps(verify(args.verify), indent=2))
    else:
        if not args.release_dir or not args.output:
            parser.error('Assembly requires --release-dir and --output')
        print(json.dumps(assemble(args.release_dir, args.output), indent=2))
