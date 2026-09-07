# Copyright 2020 Yury Kharchenko
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy at http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software distributed
# under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied. See the License for the
# specific language governing permissions and limitations under the License.
# Modified: Python data-only port of J2ME-Loader's Loader/Action, with bounded
# parsing and JSON output. Upstream revision recorded in decoder-provenance.json.
"""Portable MBAC/MTRA decoder; no Java VM or original game code execution."""
import math
import struct


class Reader:
    def __init__(self, data):
        self.data, self.pos, self.cache, self.cached = data, 0, 0, 0

    def take(self, count):
        if count < 0 or self.pos + count > len(self.data):
            raise ValueError('Truncated Micro3D resource')
        value = self.data[self.pos:self.pos + count]
        self.pos += count
        return value

    def u8(self): return self.take(1)[0]
    def u16(self): return struct.unpack('<H', self.take(2))[0]
    def s16(self): return struct.unpack('<h', self.take(2))[0]
    def i32(self): return struct.unpack('<i', self.take(4))[0]

    def bits(self, count, signed=False):
        if not 0 <= count <= 32: raise ValueError('Invalid bit width')
        while self.cached < count:
            self.cache |= self.u8() << self.cached
            self.cached += 8
        value = self.cache & ((1 << count) - 1)
        self.cache >>= count
        self.cached -= count
        return value - (1 << count) if signed and count and value & (1 << (count-1)) else value

    def align(self): self.cache = self.cached = 0
    def matrix(self): return [self.s16() * (1 if i % 4 == 3 else 1/4096) for i in range(12)]

    def header(self, magic):
        if self.take(2) != magic: raise ValueError('Invalid Micro3D signature')
        version = self.u8()
        if self.u8() or version not in range(2, 6): raise ValueError('Unsupported Micro3D version')
        return version


def model(data):
    r = Reader(data); version = r.header(b'MB')
    vf, nf, pf, bf = [r.u8() for _ in range(4)] if version > 3 else [1, 0, 1, 1]
    nv, t3, t4, nb = [r.u16() for _ in range(4)]
    c3, c4, nt, np, nc = [r.u16() for _ in range(5)] if pf >= 3 else [0, 0, 1, 1, 0]
    if bf != 1 or nv > 21845 or nb > nv or nt > 16 or not 1 <= np <= 33 or nc > 256:
        raise ValueError('Invalid model dimensions')
    patterns = [[[r.u16(), r.u16()] for _ in range(nt+1)] for _ in range(np)] if version == 5 else [[[c3, c4], [t3, t4]]]
    vertices = []
    if vf == 1: vertices = [r.s16() for _ in range(nv*3)]
    elif vf == 2:
        while len(vertices) < nv*3:
            chunk = r.bits(8); count = ((chunk & 63)+1)*3
            if len(vertices)+count > nv*3: raise ValueError('Oversized vertex block')
            vertices.extend(r.bits([8, 10, 13, 16][chunk >> 6], True) for _ in range(count))
    else: raise ValueError('Unsupported vertex encoding')
    r.align(); normals = []
    if nf == 1: normals = [r.s16() for _ in range(nv*3)]
    elif nf == 2:
        for _ in range(nv):
            x = r.bits(7)
            if x == 64:
                kind = r.bits(3)
                if kind > 5: raise ValueError('Invalid normal')
                z, y, x = [0, 0, 64, 0, 0, -64, 0, 0][kind:kind+3]
            else:
                x = x-128 if x & 64 else x; y = r.bits(7, True); sign = r.bits(1)
                z = math.floor(math.sqrt(max(0, 4096-x*x-y*y))+.5) * (-1 if sign else 1)
            normals.extend([x, y, z])
    elif nf != 0: raise ValueError('Unsupported normal encoding')
    r.align()

    def polygon(indices, attrs, material, face):
        if any(i >= nv for i in indices): raise ValueError('Vertex index outside model')
        order = [0, 1, 2] if len(indices) == 3 else [0, 1, 2, 2, 1, 3]
        return dict(indices=[indices[i] for i in order], attributes=[v & 255 for i in order for v in attrs[i]],
                    texture=face, pattern=0, blend=material & 6, double_sided=bool(material & 16))

    colored, textured = [], []
    if c3+c4:
        mb, ib, cb, ci, _ = [r.u8() for _ in range(5)]
        palette = [[r.bits(cb) for _ in range(3)] for _ in range(nc)]
        for i in range(c3+c4):
            m = r.bits(mb) << 1
            if m & 0xFC09: raise ValueError('Invalid colored material')
            indices = [r.bits(ib) for _ in range(3 if i < c3 else 4)]
            color = r.bits(ci)
            if color >= nc: raise ValueError('Invalid palette index')
            attrs = [palette[color]+[(m & 32) >> 5, (m & 64) >> 6]] * len(indices)
            colored.append(polygon(indices, attrs, m, -1))
    if t3+t4:
        if pf == 2: mb, ib, uv = r.u8(), r.u8(), 7
        elif pf == 3: mb, ib, uv, _ = [r.bits(8) for _ in range(4)]
        elif pf != 1: raise ValueError('Unsupported polygon encoding')
        for i in range(t3+t4):
            count = 3 if i < t3 else 4
            if pf == 1:
                m = r.u16()
                if m & (0xFFF9 if count == 3 else 0xFFF8) or (count == 4 and not m & 1): raise ValueError('Invalid material')
                indices = [r.u16() for _ in range(count)]
                m = (m & 4) << 2 | (m & 2) >> 1
                attrs = [[r.u8(), r.u8(), 1, 0, m & 1] for _ in indices]
            else:
                m = r.bits(mb)
                if m & (0xFF88 if pf == 2 else 0xFC08): raise ValueError('Invalid material')
                indices = [r.bits(ib) for _ in range(count)]
                attrs = [[r.bits(uv), r.bits(uv), (m & 32) >> 5, (m & 64) >> 6, m & 1] for _ in indices]
            textured.append(polygon(indices, attrs, m, -1))
    r.align()
    cursor = [0, c3, 0, t3]
    for i, groups in enumerate(patterns):
        pattern = 0 if i == 0 else 1 << (i % 32)
        if pattern >= 2**31: pattern -= 2**32
        for face, counts in enumerate(groups):
            polys = colored if face == 0 else textured
            for kind, count in enumerate(counts):
                slot = kind + (0 if face == 0 else 2)
                for _ in range(count):
                    if cursor[slot] >= len(polys): raise ValueError('Invalid pattern counts')
                    p = polys[cursor[slot]]; p['pattern'] = pattern
                    if face: p['texture'] = face-1
                    cursor[slot] += 1
    bones = []
    for i in range(nb):
        count, parent = r.u16(), r.s16()
        if parent < -1 or parent >= i: raise ValueError('Invalid bone parent')
        bones.append(dict(vertices=count, parent=parent, matrix=r.matrix()))
    if sum(b['vertices'] for b in bones) != nv: raise ValueError('Invalid bone vertex blocks')
    return dict(vertices=vertices, normals=normals, polygons=textured+colored, bones=bones, patterns=np)


IDENTITY = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0]


def sample(track, frame):
    if frame >= track[-1][0]: return track[-1][1]
    for i in range(len(track)-2, -1, -1):
        key, values = track[i]
        if frame < key: continue
        next_key, after = track[i+1]; amount = (frame-key)/(next_key-key)
        return [a+(b-a)*amount for a, b in zip(values, after)]
    return [0] * len(track[0][1])


def bone_matrix(bone, frame):
    if 'matrix' in bone: return bone['matrix'][:]
    m = IDENTITY[:]
    if 'translate' in bone: m[3], m[7], m[11] = sample(bone['translate'], frame)
    x, y, z = sample(bone['rotate'], frame)
    if x == 0 and y == 0:
        if z < 0: m[5] = m[10] = -1
    else:
        length = math.sqrt(x*x+y*y+z*z); x, y, z = x/length, y/length, z/length
        length = math.hypot(x, y); rx, ry = -y/length, x/length
        s, nc = math.sqrt(max(0, 1-z*z)), 1-z
        m[0], m[1], m[2] = rx*rx*nc+z, rx*ry*nc, ry*s
        m[4], m[5], m[6] = rx*ry*nc, ry*ry*nc+z, -rx*s
        m[8], m[9], m[10] = -ry*s, rx*s, z
    if 'roll' in bone:
        angle = sample(bone['roll'], frame)[0]; c, s = math.cos(angle), math.sin(angle)
        for row in (0, 4, 8):
            a, b = m[row:row+2]; m[row], m[row+1] = a*c+b*s, b*c-a*s
    if 'scale' in bone:
        scale = sample(bone['scale'], frame)
        for row in (0, 4, 8):
            for col in range(3): m[row+col] *= scale[col]
    return m


def animation(data):
    r = Reader(data); version = r.header(b'MT'); actions, nb = r.u16(), r.u16()
    r.take(20)
    if actions > 256 or nb > 256: raise ValueError('Animation exceeds limits')
    out = []; total = 0
    def track(width=3, factor=1):
        count = r.u16()
        if not 1 <= count <= 4096: raise ValueError('Invalid animation track')
        values = [(r.u16(), [r.s16()*factor for _ in range(width)]) for _ in range(count)]
        if any(a[0] >= b[0] for a, b in zip(values, values[1:])): raise ValueError('Unsorted animation track')
        return values
    for _ in range(actions):
        last = r.u16(); total += (last+1)*nb*12
        if total > 4_000_000: raise ValueError('Animation exceeds limits')
        bones = []
        for _ in range(nb):
            kind = r.u8(); bone = {}
            if kind == 0: bone['matrix'] = r.matrix()
            elif kind == 1: bone['matrix'] = IDENTITY[:]
            elif kind in (2, 3, 4, 5, 6):
                if kind in (2, 6): bone['translate'] = track()
                if kind == 3: bone['translate'] = [(0, [r.s16() for _ in range(3)])]
                if kind == 2: bone['scale'] = track(factor=1/4096)
                bone['rotate'] = track()
                if kind == 3: bone['roll'] = [(0, [r.s16()*math.tau/4096])]
                elif kind != 5: bone['roll'] = track(1, math.tau/4096)
            else: raise ValueError('Unsupported animation bone')
            bones.append(bone)
        patterns = {str(r.u16()): r.i32() for _ in range(r.u16())} if version == 5 else {}
        frames = [[v for bone in bones for v in bone_matrix(bone, f)] for f in range(last+1)]
        out.append(dict(last_frame=last, matrices=frames, patterns=patterns))
    return out
