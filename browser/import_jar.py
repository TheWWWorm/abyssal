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
import m3g
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
    return png(width, abs(height), rows)


PNG_SIGNATURE = b'\x89PNG\r\n\x1a\n'


def png(width, height, rows):
    """RGBA PNG from filtered scanlines (filter byte 0 then RGBA texels)."""
    def chunk(kind, payload):
        return struct.pack('>I', len(payload))+kind+payload+struct.pack('>I', zlib.crc32(kind+payload))
    return PNG_SIGNATURE+chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))+chunk(b'IDAT', zlib.compress(rows))+chunk(b'IEND', b'')


def png_texels(data):
    """Decode a non-interlaced 8-bit RGB, RGBA or indexed PNG into RGBA texels."""
    if not data.startswith(PNG_SIGNATURE): raise ValueError('Invalid PNG')
    offset, header, palette, alpha, compressed = 8, None, b'', b'', bytearray()
    while offset+8 <= len(data):
        length, kind = struct.unpack_from('>I4s', data, offset)
        payload = data[offset+8:offset+8+length]; offset += 12+length
        if len(payload) != length: raise ValueError('Truncated PNG')
        if kind == b'IHDR': header = struct.unpack('>IIBBBBB', payload)
        elif kind == b'PLTE': palette = payload
        elif kind == b'tRNS': alpha = payload
        elif kind == b'IDAT': compressed += payload
        elif kind == b'IEND': break
    if header is None: raise ValueError('Invalid PNG')
    width, height, depth, colour, _, _, interlace = header
    channels = {2: 3, 3: 1, 6: 4}.get(colour)
    if depth != 8 or channels is None or interlace or not 0 < width <= 4096 or not 0 < height <= 4096: raise ValueError('Unsupported PNG encoding')
    inflater = zlib.decompressobj(); raw = inflater.decompress(bytes(compressed), (width*channels+1)*height+1)
    stride = width*channels
    if len(raw) != (stride+1)*height: raise ValueError('Invalid PNG pixels')
    texels, previous = bytearray(), bytearray(stride)
    for y in range(height):
        kind, line = raw[y*(stride+1)], bytearray(raw[y*(stride+1)+1:(y+1)*(stride+1)])
        for i in range(stride):
            a = line[i-channels] if i >= channels else 0; b = previous[i]; c = previous[i-channels] if i >= channels else 0
            if kind == 1: line[i] = (line[i]+a) & 255
            elif kind == 2: line[i] = (line[i]+b) & 255
            elif kind == 3: line[i] = (line[i]+(a+b)//2) & 255
            elif kind == 4:
                p = a+b-c; pa, pb, pc = abs(p-a), abs(p-b), abs(p-c)
                line[i] = (line[i]+(a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
            elif kind: raise ValueError('Invalid PNG filter')
        for x in range(width):
            if colour == 6: texels += line[x*4:x*4+4]
            elif colour == 2: texels += line[x*3:x*3+3]+b'\xff'
            else:
                index = line[x]
                if index*3+3 > len(palette): raise ValueError('PNG palette index outside table')
                texels += palette[index*3:index*3+3]+bytes([alpha[index] if index < len(alpha) else 255])
        previous = line
    return width, height, texels


def translucence(width, height, texels):
    """The atlas's alpha as the translucent faces read it. The low-detail
    build dithers its atlases to fully clear or solid texels where the full
    build has partial alpha, about as many solid as the alpha was high; the
    share of solid texels around each texel recovers that alpha."""
    alpha = bytes(texels[3::4])
    if any(16 <= level <= 239 for level in alpha): return alpha
    out = bytearray(len(alpha))
    for y in range(height):
        for x in range(width):
            near = [alpha[min(height-1, max(0, y+j))*width+min(width-1, max(0, x+i))] for j in (-1, 0, 1) for i in (-1, 0, 1)]
            out[y*width+x] = round(sum(near)/9)
    return bytes(out)


def m3g_atlas(width, height, texels, glows, alpha=None):
    """The JSR-184 edition's RGBA atlas. Texels its glows sample have their
    colour multiplied by their alpha (as translucence reads it), so they add
    only their own light; the alpha still keys the cut-out and
    half-transparent faces."""
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            r, g, b, a = texels[(y*width+x)*4:(y*width+x)*4+4]
            light = alpha[y*width+x] if alpha else a
            rows += bytes([r*light//255, g*light//255, b*light//255, a] if (x, y) in glows else [r, g, b, a])
    return png(width, height, rows)


def emblem_patterns(model_id):
    """Frame -> emblem pattern, and the last frame shown. The JSR-184 renderer
    moves a part's emblem texture down an eighth or a quarter of the atlas
    from the frame range the game asks for; these tables give each part the
    same emblem for the ranges it is shown in, as the Mascot Capsule
    animations do for theirs."""
    if 0 <= model_id < 12: return ({'0': 2, '3': 4, '6': 8}, 8) if model_id in (2, 4, 5, 6, 7, 8) else ({'0': 2, '1': 4, '2': 8}, 2)
    if model_id in (3307, 3308): return {'0': 2, '3': 4}, 5
    if model_id in (3300, 3311): return {'0': 2, '2': 4}, 3
    if model_id in (3305, 3306, 3309, 3310): return {'0': 2, '2': 4}, 2
    return {'0': 2, '1': 4, '2': 8}, 2


def convert_m3g(root, models):
    """Write the engine's model data for every registered model the JAR
    stores as M3G, beside its name in the engine's model convention, and the
    atlases those models sample."""
    root = pathlib.Path(root); atlases, glows, converted = {}, {}, []
    for record in models:
        for texture in record['textures']:
            source = root/(texture[:-4]+'.png')
            if texture in atlases or not texture.endswith('.bmp') or not source.is_file(): continue
            width, height, texels = png_texels(source.read_bytes())
            atlases[texture] = width, height, texels, translucence(width, height, texels); glows[texture] = set()
    for record in models:
        source = root/(record['model'][:-5]+'.m3g')
        if not record['model'].endswith('.mbac') or not source.is_file(): continue
        texture = record['textures'][0]; atlas = atlases.get(texture)
        shape, frames = m3g.model(source.read_bytes(), (atlas[0], atlas[1], atlas[3]) if atlas else None)
        if atlas:
            for polygon in shape['polygons']:
                if polygon['blend'] == 4:
                    corners = list(zip(polygon['attributes'][0::5], polygon['attributes'][1::5]))
                    glows[texture].update(m3g.covered(atlas[0], atlas[1], corners))
        if frames and shape['patterns'] > 1:
            patterns, last = emblem_patterns(int(record['id']))
            action = frames[0]
            action['matrices'] += [action['matrices'][-1]]*(last-action['last_frame'])
            action['last_frame'] = max(last, action['last_frame']); action['patterns'] = patterns
        target = root/record['model']
        pathlib.Path(str(target)+'.json').write_text(json.dumps(shape, separators=(',', ':')))
        if frames: target.with_suffix('.mtra.json').write_text(json.dumps(frames, separators=(',', ':')))
        converted.append(record['model'])
    for texture, (width, height, texels, alpha) in atlases.items():
        pathlib.Path(str(root/texture)+'.png').write_bytes(m3g_atlas(width, height, texels, glows[texture], alpha))
    return converted


def salvage(archive, entry):
    """Read a damaged entry by inflating the bytes it actually has.

    One circulating copy of the 1.0.8 JAR was repacked with its last entry a byte
    short: the deflate stream stops one byte before its end-of-block marker, on
    top of the next local header. Every byte of the file itself is still there,
    so the entry is accepted when what inflates is exactly the declared size
    with the declared CRC, and refused otherwise.
    """
    fp = archive.fp
    fp.seek(entry.header_offset)
    header = fp.read(30)
    if len(header) < 30 or header[:4] != b'PK\x03\x04': raise ValueError('Damaged JAR entry: ' + entry.filename)
    name_length, extra_length = struct.unpack_from('<HH', header, 26)
    start = entry.header_offset+30+name_length+extra_length
    following = [info.header_offset for info in archive.infolist() if info.header_offset > entry.header_offset]
    limit = min(following+[archive.start_dir])
    fp.seek(start)
    raw = fp.read(max(0, limit-start))
    if entry.compress_type == zipfile.ZIP_STORED: data = raw[:entry.file_size]
    elif entry.compress_type == zipfile.ZIP_DEFLATED:
        try: data = zlib.decompressobj(-15).decompress(raw)[:entry.file_size]
        except zlib.error as error: raise ValueError('Damaged JAR entry: ' + entry.filename) from error
    else: raise ValueError('Damaged JAR entry: ' + entry.filename)
    if len(data) != entry.file_size or zlib.crc32(data) != entry.CRC: raise ValueError('Damaged JAR entry: ' + entry.filename)
    return data


def read_entry(archive, entry):
    try: return archive.read(entry)
    except (zipfile.BadZipFile, zlib.error, EOFError): return salvage(archive, entry)


def decode(jar, root, progress=lambda message: None, digest=None):
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
            data = read_entry(archive, entry)
            # The phone launcher reads its icon directly, outside the resource envelope.
            if name != launcher_icon and path.suffix in {'.mbac', '.mtra', '.bmp', '.png'}: data = unwrap(data)
            # A few M3G files are stored without the envelope.
            if path.suffix == '.m3g' and not data.startswith(m3g.IDENTIFIER): data = unwrap(data)
            # A texture is kept as one PNG, the atlas as painted: the engine keys
            # its pure white (the phone's palette index 0) on the cut-out
            # polygons itself, so a modder has one file to work with.
            if path.suffix != '.bmp': path.write_bytes(data)
            if path.suffix in {'.mbac', '.mtra'}:
                decoded = (model if path.suffix == '.mbac' else animation)(data)
                pathlib.Path(str(path)+'.json').write_text(json.dumps(decoded, separators=(',', ':')))
            if path.suffix == '.bmp':
                pathlib.Path(str(path)+'.png').write_bytes(bitmap(data))
    progress('Reading game data…')
    extract(jar, root, digest, prepare=lambda models: convert_m3g(root, models))
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
