"""JSR-184 (M3G) models of the Nokia edition, converted to the engine's model data.

The Nokia edition draws the same scenes from M3G files. They are read here as
data only and written in the shape micro3d.model and micro3d.animation give
the Mascot Capsule models: bone-ordered vertices, texel-addressed polygons,
per-frame bone matrices and pattern masks.

How the edition's renderer reads its files:
- Each root group is a separate part. A group with no animation is not drawn
  as a group: its meshes are drawn each in its own transform.
- Materials are only tags and are removed before drawing, so nothing is lit by
  the file. A part with a green-specular submesh is drawn translucent, by the
  atlas's alpha. A red-specular submesh is the faction emblem: its texture is
  shifted down an eighth or a quarter of the atlas for the second and third
  faction.
- Every mesh samples the model's registered atlas, which replaces the
  placeholder image stored in the file.
"""
import math
import struct
import zlib

IDENTIFIER = b'\xabJSR184\xbb\r\n\x1a\n'
MAX_OBJECTS = 20000
MAX_VERTICES = 21845
EMBLEM_VARIANTS = 3
ATLAS = 128

GROUP, MESH, KEYFRAMES, TRACK, CONTROLLER = 9, 14, 19, 2, 1
ORIENTATION, SCALE, TRANSLATION = 268, 270, 275
LINEAR, SLERP, SPLINE, SQUAD, STEP = 176, 177, 178, 179, 180
TRANSLUCENT_TAG, EMBLEM_TAG = 0x00FF00, 0xFF0000
CUT, HALF, GLOW = 'cut', 'half', 'glow'


class Reader:
    def __init__(self, data): self.data, self.offset = data, 0

    def take(self, count):
        if count < 0 or self.offset+count > len(self.data): raise ValueError('Truncated M3G object')
        value = self.data[self.offset:self.offset+count]; self.offset += count
        return value

    def u8(self): return self.take(1)[0]
    def flag(self): return self.u8() != 0
    def u16(self): return struct.unpack('<H', self.take(2))[0]
    def u32(self): return struct.unpack('<I', self.take(4))[0]
    def i32(self): return struct.unpack('<i', self.take(4))[0]

    def f32(self):
        value = struct.unpack('<f', self.take(4))[0]
        if not math.isfinite(value): raise ValueError('Invalid M3G number')
        return value

    def floats(self, count): return [self.f32() for _ in range(count)]
    def color(self, count): return list(self.take(count))

    def count(self, limit=65536):
        value = self.u32()
        if value > limit: raise ValueError('Oversized M3G list')
        return value

    def refs(self): return [self.u32() for _ in range(self.count())]


def object3d(r, o):
    o['user_id'] = r.u32(); o['tracks'] = r.refs()
    for _ in range(r.count()):
        r.u32(); r.take(r.count(1 << 20))


def transformable(r, o):
    object3d(r, o)
    if r.flag():
        o['translation'] = r.floats(3); o['scale'] = r.floats(3)
        o['angle'] = r.f32(); o['axis'] = r.floats(3)
    if r.flag(): o['matrix'] = r.floats(16)


def node(r, o):
    transformable(r, o)
    r.flag(); r.flag(); r.u8(); r.u32()
    if r.flag(): r.take(10)


def read_object(kind, r):
    o = {'type': kind}
    if kind == 0: r.take(2); o['external'] = r.flag(); r.u32(); r.u32(); r.take(len(r.data)-r.offset)
    elif kind == CONTROLLER:
        object3d(r, o); o['speed'] = r.f32(); o['weight'] = r.f32(); o['interval'] = [r.i32(), r.i32()]
        o['sequence_time'] = r.f32(); o['world_time'] = r.i32()
    elif kind == TRACK: object3d(r, o); o['keyframes'] = r.u32(); o['controller'] = r.u32(); o['property'] = r.u32()
    elif kind == 3:
        object3d(r, o); r.u8(); o['compositing'] = r.u32(); r.u32(); o['polygon_mode'] = r.u32(); o['material'] = r.u32(); o['textures'] = r.refs()
    elif kind == 6: object3d(r, o); r.take(6); r.floats(2)
    elif kind == 8: object3d(r, o); o['culling'] = r.u8(); r.take(5)
    elif kind == GROUP: node(r, o); o['children'] = r.refs()
    elif kind == 10:
        object3d(r, o); r.u8()
        if not r.flag(): r.u32(); r.u32(); r.take(r.count(1 << 24)); r.take(r.count(1 << 24))
        else: r.u32(); r.u32()
    elif kind == 11:
        object3d(r, o); encoding = r.u8()
        if encoding in (0, 1, 2):
            start = r.u32() if encoding == 0 else r.u8() if encoding == 1 else r.u16()
            o['indices'] = None; o['start'] = start
        elif encoding in (128, 129, 130):
            size = {128: 4, 129: 1, 130: 2}[encoding]; count = r.count()
            o['indices'] = [int.from_bytes(r.take(size), 'little') for _ in range(count)]
        else: raise ValueError('Unsupported M3G index encoding')
        o['strips'] = [r.u32() for _ in range(r.count())]
        if any(length < 3 for length in o['strips']): raise ValueError('Invalid M3G triangle strip')
    elif kind == 13:
        object3d(r, o); r.take(3); r.take(4); r.take(3); o['specular'] = r.color(3); r.f32(); r.flag()
    elif kind == MESH:
        node(r, o); o['vertices'] = r.u32(); o['submeshes'] = [(r.u32(), r.u32()) for _ in range(r.count())]
    elif kind == 17:
        transformable(r, o); o['image'] = r.u32(); r.take(3); r.take(5)
    elif kind == KEYFRAMES:
        object3d(r, o); o['interpolation'] = r.u8(); o['repeat'] = r.u8(); encoding = r.u8()
        o['duration'] = r.u32(); o['valid'] = [r.u32(), r.u32()]
        width, count = r.count(16), r.count()
        if not 1 <= width <= 16 or count < 1: raise ValueError('Invalid M3G keyframes')
        keys = []
        if encoding == 0:
            for _ in range(count): keys.append((r.u32(), r.floats(width)))
        elif encoding in (1, 2):
            bias, scale = r.floats(width), r.floats(width); top = 255 if encoding == 1 else 65535
            for _ in range(count):
                time = r.u32(); raw = [r.u8() if encoding == 1 else r.u16() for _ in range(width)]
                keys.append((time, [b+s*v/top for b, s, v in zip(bias, scale, raw)]))
        else: raise ValueError('Unsupported M3G keyframe encoding')
        o['keys'] = keys
    elif kind == 20:
        object3d(r, o); size, width, encoding, count = r.u8(), r.u8(), r.u8(), r.u16()
        if size not in (1, 2) or not 2 <= width <= 4 or encoding not in (0, 1): raise ValueError('Invalid M3G vertex array')
        fmt = '<'+('b' if size == 1 else 'h')*width; step = size*width
        rows, last = [], [0]*width
        for _ in range(count):
            row = list(struct.unpack(fmt, r.take(step)))
            if encoding:
                top = 1 << (8*size)
                row = [((a+b+top//2) % top)-top//2 for a, b in zip(last, row)]; last = row
            rows.append(row)
        o['rows'] = rows
    elif kind == 21:
        object3d(r, o); r.take(4); o['positions'] = r.u32(); o['position_bias'] = r.floats(3); o['position_scale'] = r.f32()
        o['normals'] = r.u32(); r.u32()
        o['texcoords'] = [(r.u32(), r.floats(3), r.f32()) for _ in range(r.count(8))]
    else: raise ValueError('Unsupported M3G object type %d' % kind)
    if r.offset != len(r.data): raise ValueError('Unexpected M3G object length')
    return o


def objects(data):
    if not data.startswith(IDENTIFIER): raise ValueError('Not an M3G file')
    out, offset = [None], len(IDENTIFIER)
    while offset < len(data):
        if offset+13 > len(data): raise ValueError('Truncated M3G section')
        compression, total, size = struct.unpack_from('<BII', data, offset)
        if total < 13 or offset+total > len(data) or size > 1 << 24: raise ValueError('Invalid M3G section')
        body = data[offset+9:offset+total-4]
        if zlib.adler32(data[offset:offset+total-4]) != struct.unpack_from('<I', data, offset+total-4)[0]:
            raise ValueError('M3G section checksum mismatch')
        offset += total
        if compression == 1:
            inflater = zlib.decompressobj(); body = inflater.decompress(body, size+1)
            if inflater.unconsumed_tail or not inflater.eof: raise ValueError('Invalid M3G section')
        elif compression: raise ValueError('Unsupported M3G compression')
        if len(body) != size: raise ValueError('Invalid M3G section size')
        cursor = 0
        while cursor < len(body):
            if cursor+5 > len(body): raise ValueError('Truncated M3G object')
            kind, length = struct.unpack_from('<BI', body, cursor)
            if cursor+5+length > len(body): raise ValueError('Truncated M3G object')
            out.append(read_object(kind, Reader(body[cursor+5:cursor+5+length]))); cursor += 5+length
            if len(out) > MAX_OBJECTS: raise ValueError('M3G file exceeds limits')
    if len(out) < 2 or out[1]['type'] != 0 or out[1]['external']: raise ValueError('Unsupported M3G header')
    return out


def multiply(a, b):
    """3x4 row-major affine matrices, as the model data stores them."""
    out = []
    for row in range(3):
        for column in range(4):
            value = sum(a[row*4+k]*b[k*4+column] for k in range(3))
            out.append(value+a[row*4+3] if column == 3 else value)
    return out


def inverse(m):
    a, b, c, d, e, f, g, h, i = m[0], m[1], m[2], m[4], m[5], m[6], m[8], m[9], m[10]
    det = a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g)
    if abs(det) < 1e-12: raise ValueError('Singular M3G transform')
    r = [(e*i-f*h)/det, (c*h-b*i)/det, (b*f-c*e)/det, (f*g-d*i)/det, (a*i-c*g)/det, (c*d-a*f)/det,
         (d*h-e*g)/det, (b*g-a*h)/det, (a*e-b*d)/det]
    t = [m[3], m[7], m[11]]
    return [r[0], r[1], r[2], -sum(r[k]*t[k] for k in range(3)),
            r[3], r[4], r[5], -sum(r[3+k]*t[k] for k in range(3)),
            r[6], r[7], r[8], -sum(r[6+k]*t[k] for k in range(3))]


def quaternion(x, y, z, w):
    length = math.sqrt(x*x+y*y+z*z+w*w) or 1.0
    x, y, z, w = x/length, y/length, z/length, w/length
    return [1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w), 0,
            2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w), 0,
            2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y), 0]


def axis_angle(angle, axis):
    length = math.sqrt(sum(v*v for v in axis))
    if not length or not angle: return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0]
    half = math.radians(angle)/2; s = math.sin(half)/length
    return quaternion(axis[0]*s, axis[1]*s, axis[2]*s, math.cos(half))


def compose(translation, orientation, scale, general):
    m = [scale[0], 0, 0, 0, 0, scale[1], 0, 0, 0, 0, scale[2], 0]
    m = multiply(orientation, m)
    m[3], m[7], m[11] = translation
    if general:
        if any(abs(v) > 1e-6 for v in general[12:15]) or abs(general[15]-1) > 1e-6:
            raise ValueError('Projective M3G transform')
        m = multiply(m, general[:12])
    return m


def slerp(a, b, amount):
    dot = sum(x*y for x, y in zip(a, b))
    if dot < 0: b, dot = [-v for v in b], -dot
    if dot > 0.9995: return [x+(y-x)*amount for x, y in zip(a, b)]
    theta = math.acos(min(1.0, dot)); s = math.sin(theta)
    return [(x*math.sin((1-amount)*theta)+y*math.sin(amount*theta))/s for x, y in zip(a, b)]


def sample(sequence, controller, world):
    """KeyframeSequence value at a world time, per JSR-184 section 7 (constant
    repeat; the edition uses no looping sequences)."""
    time = controller['sequence_time']+controller['speed']*(world-controller['world_time'])
    first, last = sequence['valid']
    keys = sequence['keys'][first:last+1] or sequence['keys'][:1]
    # Of keys sharing a time the last one holds from that time on; some
    # exported scale tracks open with a stray key before the real one.
    keys = [key for i, key in enumerate(keys) if i+1 == len(keys) or keys[i+1][0] != key[0]]
    if time <= keys[0][0] or len(keys) == 1: return keys[0][1]
    if time >= keys[-1][0]: return keys[-1][1]
    for i in range(len(keys)-1):
        (t0, v0), (t1, v1) = keys[i], keys[i+1]
        if time >= t1: continue
        amount = (time-t0)/(t1-t0) if t1 > t0 else 0.0
        kind = sequence['interpolation']
        if kind == STEP: return v0
        if kind in (SLERP, SQUAD) and len(v0) == 4: return slerp(v0, v1, amount)
        if kind == SPLINE:
            # Catmull-Rom tangents scaled for uneven key spacing (7.5.6).
            def tangent(j):
                if j <= 0 or j >= len(keys)-1: return [0.0]*len(v0)
                (ta, va), (tb, vb) = keys[j-1], keys[j+1]
                span = (keys[j+1][0]-keys[j-1][0]) or 1
                width = (t1-t0)
                return [(b-a)*width/span for a, b in zip(va, vb)]
            m0, m1 = tangent(i), tangent(i+1); s = amount; s2, s3 = s*s, s*s*s
            return [(2*s3-3*s2+1)*a+(s3-2*s2+s)*p+(-2*s3+3*s2)*b+(s3-s2)*q for a, b, p, q in zip(v0, v1, m0, m1)]
        return [a+(b-a)*amount for a, b in zip(v0, v1)]
    return keys[-1][1]


def covered(width, height, corners):
    """The texels a face's coordinates span, as (x, y) pairs."""
    us, vs = [u for u, _ in corners], [v for _, v in corners]
    left, right = max(0, math.floor(min(us)+0.5)), min(width-1, math.floor(max(us)+0.5))
    top, bottom = max(0, math.floor(min(vs)+0.5)), min(height-1, math.floor(max(vs)+0.5))
    return [(x, y) for y in range(top, bottom+1) for x in range(left, right+1)]


def translucency(atlas, corners):
    """How a translucent part's face reads in the Mascot Capsule terms the
    engine draws: texels that are each fully clear or solid are a cut-out;
    texels at exactly half alpha are MBAC's half-transparent keyed face (the
    algae); any other alpha is a glow added to the water."""
    width, height, alpha = atlas
    levels = {alpha[y*width+x] for x, y in covered(width, height, corners)}
    partial = {level for level in levels if 16 <= level <= 239}
    if not partial: return CUT
    if all(120 <= level <= 136 for level in partial): return HALF
    return GLOW


def model(data, atlas=None):
    """Returns (model, animation) in micro3d's shapes; animation is [] for a
    still model and carries the emblem patterns for a model that has one.
    atlas is (width, height, alpha bytes) of the registered texture, in the
    texels the coordinates are written in."""
    objs = objects(data)
    def get(index, kind):
        if not 0 < index < len(objs) or objs[index]['type'] != kind: raise ValueError('Invalid M3G reference')
        return objs[index]
    referenced = {child for o in objs[1:] if o['type'] == GROUP for child in o['children']}

    def duration(index):
        o = objs[index]
        longest = max([get(get(t, TRACK)['keyframes'], KEYFRAMES)['duration'] for t in o.get('tracks', [])] or [0])
        for child in o.get('children', []): longest = max(longest, duration(child))
        return longest

    def tag(appearance):
        material = appearance['material']
        if not material: return 0
        r, g, b = get(material, 13)['specular']
        return r << 16 | g << 8 | b

    # Parts in the renderer's order: still groups split into their meshes.
    parts = []
    for index, o in enumerate(objs):
        if index == 0 or o is None or o['type'] != GROUP or index in referenced: continue
        frames = duration(index)
        if frames: parts.append((index, True))
        else: parts.extend((child, False) for child in o['children'] if objs[child]['type'] == MESH)
    if not parts: raise ValueError('M3G file has no drawable part')

    bones, nodes = [], []
    def visit(index, parent, nested):
        o = objs[index]; nodes.append((index, len(bones))); bone = len(bones)
        bones.append({'node': index, 'parent': parent})
        if nested:
            for child in o.get('children', []):
                if objs[child]['type'] in (GROUP, MESH): visit(child, bone, True)

    translucent_parts = set()
    def translucent(index):
        o = objs[index]
        if o['type'] == MESH:
            return any(tag(get(a, 3)) == TRANSLUCENT_TAG for _, a in o['submeshes'])
        return any(translucent(child) for child in o.get('children', []) if objs[child]['type'] in (GROUP, MESH))
    for index, nested in parts:
        # The exporter's root group only turns the scene upright (+90 degrees
        # about X); the Mascot Capsule models carry its children unturned, so
        # they become root bones here too.
        start = len(bones)
        for child in (objs[index]['children'] if nested else [index]):
            if objs[child]['type'] in (GROUP, MESH): visit(child, -1, nested)
        if translucent(index): translucent_parts.update(range(start, len(bones)))

    def rest(o):
        orientation = axis_angle(o.get('angle', 0), o.get('axis', [1, 0, 0]))
        return o.get('translation', [0, 0, 0]), orientation, o.get('scale', [1, 1, 1]), o.get('matrix')

    # Coordinates count the atlas's texels from their centres, as MBAC's do.
    width, height = atlas[:2] if atlas else (ATLAS, ATLAS)
    vertices, normals, polygons, out_bones = [], [], [], []
    emblem = False
    for bone_index, bone in enumerate(bones):
        o = objs[bone['node']]
        count = 0
        # The low-detail build ships some models as a placeholder mesh with no
        # vertex buffer; the renderer draws nothing for it.
        if o['type'] == MESH and (o['vertices'] or o['submeshes']):
            buffer = get(o['vertices'], 21)
            positions = get(buffer['positions'], 20)['rows']
            scale, bias = buffer['position_scale'], buffer['position_bias']
            base = len(vertices)//3; count = len(positions)
            if base+count > MAX_VERTICES: raise ValueError('M3G model exceeds vertex limit')
            for row in positions: vertices.extend(round(v*scale+b, 3) for v, b in zip(row[:3], bias))
            if buffer['normals']:
                rows = get(buffer['normals'], 20)['rows']
                if len(rows) != count: raise ValueError('M3G normals do not match positions')
                for row in rows:
                    length = math.sqrt(sum(v*v for v in row[:3])) or 1.0
                    normals.extend(round(v*4096/length) for v in row[:3])
            else: normals.extend([0, 0, 4096]*count)
            if not buffer['texcoords']: raise ValueError('M3G mesh without texture coordinates')
            array, uv_bias, uv_scale = buffer['texcoords'][0]
            uvs = get(array, 20)['rows']
            if len(uvs) != count: raise ValueError('M3G texture coordinates do not match positions')
            blended = bone_index in translucent_parts
            for strips_index, appearance_index in o['submeshes']:
                strips, appearance = get(strips_index, 11), get(appearance_index, 3)
                if not appearance['textures']: continue
                indices = strips['indices'] if strips['indices'] is not None else list(range(strips['start'], strips['start']+sum(strips['strips'])))
                if sum(strips['strips']) != len(indices) or any(i >= count for i in indices): raise ValueError('Invalid M3G strip indices')
                culled = appearance['polygon_mode'] and get(appearance['polygon_mode'], 8)['culling'] == 162
                variants = EMBLEM_VARIANTS if tag(appearance) == EMBLEM_TAG else 1
                emblem = emblem or variants > 1
                cursor = 0
                for length in strips['strips']:
                    strip = indices[cursor:cursor+length]; cursor += length
                    for i in range(length-2):
                        a, b, c = strip[i:i+3]
                        # Strips alternate their turn; the Mascot Capsule data
                        # the engine reads lists each face the other way round.
                        if not i % 2: a, b = b, a
                        if len({a, b, c}) < 3: continue
                        for variant in range(variants):
                            corners = []
                            for corner in (a, b, c):
                                u, v = uvs[corner][:2]
                                corners.append((round((u*uv_scale+uv_bias[0])*width-0.5, 3),
                                                round((v*uv_scale+uv_bias[1]+variant/8)*height-0.5, 3)))
                            look = (translucency(atlas, corners) if atlas else GLOW) if blended else None
                            keyed = look in (CUT, HALF)
                            attributes = [value for u, v in corners for value in (u, v, 0 if look == GLOW else 1, 0, int(keyed))]
                            polygons.append({'indices': [base+a, base+b, base+c], 'attributes': attributes, 'texture': 0,
                                             'pattern': 0 if variants == 1 else 2 << variant,
                                             'blend': {GLOW: 4, HALF: 2}.get(look, 0), 'double_sided': bool(blended or culled)})
        out_bones.append({'vertices': count, 'parent': bone['parent'], 'matrix': compose(*rest(o))})

    shape = {'vertices': vertices, 'normals': normals, 'polygons': polygons, 'bones': out_bones,
             'patterns': 1+EMBLEM_VARIANTS if emblem else 1}

    last = max(duration(index) for index, nested in parts if nested) if any(nested for _, nested in parts) else 0
    if not last and not emblem: return shape, []
    frames = []
    for frame in range(last+1):
        matrices = []
        for bone in bones:
            o = objs[bone['node']]
            translation, orientation, scale, general = rest(o)
            for track_index in o.get('tracks', []):
                track = get(track_index, TRACK)
                value = sample(get(track['keyframes'], KEYFRAMES), get(track['controller'], CONTROLLER), frame)
                if track['property'] == TRANSLATION and len(value) == 3: translation = value
                elif track['property'] == SCALE and len(value) in (1, 3): scale = value*3 if len(value) == 1 else value
                elif track['property'] == ORIENTATION and len(value) == 4: orientation = quaternion(*value)
            # The engine applies each frame after the rest pose.
            matrices.extend(multiply(inverse(compose(*rest(o))), compose(translation, orientation, scale, general)))
        frames.append(matrices)
    return shape, [{'last_frame': last, 'matrices': frames, 'patterns': {'0': 2} if emblem else {}}]
