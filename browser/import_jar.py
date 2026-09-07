"""Resource-only JAR conversion, runnable in CPython or a Pyodide web worker.

The selected JAR is data input. Its classes are read only by the restricted
class-data evaluator; no Java VM, application methods or constructors run.
"""
import hashlib
import io
import json
import pathlib
import re
import struct
import zipfile
import zlib
from micro3d import model, animation
from extract_data import extract

# The engine is developed against the Sony Ericsson release of DEEP 1.0.8, whose
# digest is recorded here. Any DEEP MIDlet is accepted; conversion succeeds when
# the build's data layout matches the declarative profile in extract_data.
VERIFIED = 'a247f8a872dda268ed8138086bd0de6d038d7faf7ef31469b0efe3eb54209d26'
MAX_TOTAL = 128*1024*1024


def unwrap(data):
    data = bytearray(data); n = len(data)
    count = 10+n%10 if n < 100 else 50+n%20 if n < 200 else 80+n%20 if n < 300 else 100+n%50
    if n < count: raise ValueError('Resource envelope is too short')
    for i in range(count): data[i], data[n-1-i] = data[n-1-i], data[i]
    return bytes(data)


def bitmap(data, alpha=False):
    """Decode uncompressed indexed Windows BMP into PNG using only the stdlib."""
    if data[:2] != b'BM' or len(data) < 54: raise ValueError('Invalid BMP')
    offset, header = struct.unpack_from('<II', data, 10)
    width, height, planes, bits, compression = struct.unpack_from('<iiHHI', data, 18)
    if header != 40 or planes != 1 or bits != 8 or compression or not 0 < width <= 4096 or not 0 < abs(height) <= 4096:
        raise ValueError('Unsupported BMP encoding')
    palette_count = struct.unpack_from('<I', data, 46)[0] or 256
    if not 1 <= palette_count <= 256 or offset < 54+palette_count*4: raise ValueError('Invalid BMP palette')
    stride = (width+3)//4*4
    if offset+abs(height)*stride > len(data): raise ValueError('Truncated BMP pixels')
    palette = [bytes([data[54+i*4+2], data[54+i*4+1], data[54+i*4], 0 if alpha and i == 0 else 255]) for i in range(palette_count)]
    rows = bytearray()
    for y in range(abs(height)):
        src = offset+(abs(height)-1-y if height > 0 else y)*stride
        rows.append(0)
        for index in data[src:src+width]:
            if index >= palette_count: raise ValueError('BMP palette index outside table')
            rows.extend(palette[index])
    def chunk(kind, payload):
        return struct.pack('>I', len(payload))+kind+payload+struct.pack('>I', zlib.crc32(kind+payload))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR', struct.pack('>IIBBBBB', width, abs(height), 8, 6, 0, 0, 0))+chunk(b'IDAT', zlib.compress(rows))+chunk(b'IEND', b'')


def decode(jar, root, progress=lambda message: None):
    jar, root = pathlib.Path(jar), pathlib.Path(root)
    if jar.stat().st_size > 16*1024*1024: raise ValueError('JAR exceeds 16 MiB.')
    # Decide acceptance before anything is written, so a rejected JAR leaves no output.
    try:
        with zipfile.ZipFile(jar) as archive:
            manifest = archive.read('META-INF/MANIFEST.MF').decode('utf-8').replace('\r\n', '\n').replace('\n ', '')
    except (OSError, KeyError, ValueError, UnicodeDecodeError, zipfile.BadZipFile) as error:
        raise ValueError('Unsupported JAR: not a readable MIDlet archive.') from error
    fields = dict(line.split(': ', 1) for line in manifest.splitlines() if ': ' in line)
    midlet = [part.strip() for part in fields.get('MIDlet-1', '').split(',')]
    if len(midlet) != 3 or midlet[2] != 'DeepMIDlet': raise ValueError('Unsupported JAR: this is not a DEEP MIDlet.')
    launcher_icon = midlet[1].lstrip('/')
    root.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(jar) as archive:
        entries = archive.infolist()
        if len(entries) > 4096 or sum(e.file_size for e in entries) > MAX_TOTAL: raise ValueError('JAR exceeds import limits')
        names = set()
        for i, entry in enumerate(entries):
            name = entry.filename
            if entry.is_dir(): continue
            if name in names or not re.fullmatch(r'[A-Za-z0-9_./-]+', name) or '..' in name.split('/') or name.startswith('/'):
                raise ValueError('Unsafe JAR entry')
            names.add(name)
            if entry.file_size > 16*1024*1024 or entry.flag_bits & 1: raise ValueError('Unsupported JAR entry')
            if not name.startswith('data/'): continue
            if i % 30 == 0: progress('Decoding resources: %d%%' % (i*100//len(entries)))
            path = root/name; path.parent.mkdir(parents=True, exist_ok=True)
            data = archive.read(entry)
            # The phone launcher reads its icon directly, outside the resource envelope.
            if name != launcher_icon and path.suffix in {'.mbac', '.mtra', '.bmp', '.png'}: data = unwrap(data)
            path.write_bytes(data)
            if path.suffix in {'.mbac', '.mtra'}:
                decoded = (model if path.suffix == '.mbac' else animation)(data)
                pathlib.Path(str(path)+'.json').write_text(json.dumps(decoded, separators=(',', ':')))
            if path.suffix == '.bmp':
                pathlib.Path(str(path)+'.png').write_bytes(bitmap(data))
                pathlib.Path(str(path)+'.alpha.png').write_bytes(bitmap(data, True))
    progress('Reading game data…')
    extract(jar, root)
    return [p.relative_to(root).as_posix() for p in sorted(root.rglob('*')) if p.suffix in {'.mid', '.amr'}]


def pack(root):
    root = pathlib.Path(root); records = {}; total = 0
    # The pack is keyed by the digest of the JAR it came from, recorded during extraction.
    profile = json.loads((root/'native-data.json').read_text()).get('jar_sha256', '')
    if not re.fullmatch(r'[0-9a-f]{64}', profile): raise ValueError('Converted content has no JAR digest')
    paths = [root/n for n in ('native-data.json', 'resource_registry.json', 'bindings.json')]
    paths += sorted(p for p in (root/'data').rglob('*') if p.is_file())
    for path in paths:
        name = path.relative_to(root).as_posix(); data = path.read_bytes(); total += len(data)
        if not re.fullmatch(r'[a-z0-9_./-]+', name) or '..' in name.split('/') or path.suffix in {'.class', '.jar', '.js', '.py', '.gd', '.exe', '.dll', '.so'}:
            raise ValueError('Non-resource entry in content pack')
        if len(data) > 32*1024*1024 or total > MAX_TOTAL: raise ValueError('Decoded content exceeds limits')
        if path.suffix in {'.mid', '.amr'} and not pathlib.Path(str(path)+'.wav').is_file(): raise ValueError('Missing decoded audio')
        records[name] = {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
    if len(records) > 4095: raise ValueError('Too many decoded resources')
    output = io.BytesIO()
    # Stored ZIP avoids recompressing PCM and gives the Godot installer a bounded,
    # predictable allocation. This private pack is never sent across the network.
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_STORED) as archive:
        archive.writestr('pack.json', json.dumps({'format':'abyssal-content-1', 'profile':profile, 'files':records}, separators=(',', ':')))
        for path in paths: archive.write(path, path.relative_to(root).as_posix())
    return output.getvalue()
