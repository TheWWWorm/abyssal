#!/usr/bin/env python3
"""Prepare an exported Web build for a static host with a per-file size limit.

Cloudflare rejects assets larger than 25 MiB, and the Godot engine binary
exceeds that. Oversized files are split into numbered parts that worker.js
streams back together under the original path. The parts stay uncompressed:
Cloudflare negotiates its own Content-Encoding for the response, so storing
them pre-compressed would only fight that and strip the encoding header.
Release archives keep whole files, so they stay portable to hosts with no
size limit.
"""
import argparse, pathlib, shutil

LIMIT = 25 * 1024 * 1024
CHUNK = 20 * 1024 * 1024
BASE_HEADERS = """# Served by static hosts that read _headers.
# The single-threaded Web export needs no cross-origin isolation.
/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer

/*.wasm
  Content-Type: application/wasm

# Game packs carry a content hash in their filename, so they never change in place.
/*.pck
  Cache-Control: public, max-age=31536000, immutable

/importer/vendor/*
  Cache-Control: public, max-age=604800
"""


def split(path, chunk=CHUNK):
    """Replace a file with sequential .part0, .part1, ... siblings."""
    raw = path.read_bytes()
    parts = [raw[offset:offset + chunk] for offset in range(0, len(raw), chunk)]
    for index, payload in enumerate(parts):
        path.with_name(f'{path.name}.part{index}').write_bytes(payload)
    path.unlink()
    return len(raw), len(parts)


def prepare(source, output, limit=LIMIT, chunk=CHUNK):
    if chunk > limit:
        raise ValueError('Chunk size must not exceed the host limit')
    source, output = pathlib.Path(source), pathlib.Path(output)
    if output.exists():
        shutil.rmtree(output)
    shutil.copytree(source, output, symlinks=False)
    divided = []
    for path in sorted(output.rglob('*')):
        if path.is_file() and path.stat().st_size > limit:
            size, count = split(path, chunk)
            name = '/' + path.relative_to(output).as_posix()
            divided.append(name)
            print(f'  split {name}: {size/1048576:.1f} MiB into {count} parts')
    (output/'_headers').write_text(BASE_HEADERS)
    over = [p for p in output.rglob('*') if p.is_file() and p.stat().st_size > limit]
    if over:
        raise ValueError('Still over the host limit: ' + ', '.join(p.name for p in over))
    return {'files': sum(1 for p in output.rglob('*') if p.is_file()), 'split': len(divided)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=pathlib.Path, help='Exported Web build directory')
    parser.add_argument('--output', required=True, type=pathlib.Path, help='Directory to write, replaced if present')
    parser.add_argument('--limit', type=int, default=LIMIT, help='Per-file host limit in bytes')
    parser.add_argument('--chunk', type=int, default=CHUNK, help='Maximum size of each written part')
    args = parser.parse_args()
    print(prepare(args.source, args.output, args.limit, args.chunk))


if __name__ == '__main__':
    main()
