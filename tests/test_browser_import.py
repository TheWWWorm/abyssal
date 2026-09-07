"""Synthetic portable decoder and pack boundary regressions; no game fixtures."""
import hashlib, io, json, pathlib, struct, sys, tempfile, unittest, zipfile
sys.path[:0] = [str(pathlib.Path(__file__).resolve().parents[1]/p) for p in ('browser','tools')]
from micro3d import Reader, model, animation, bone_matrix
from import_jar import bitmap, decode, pack

class BrowserImportTests(unittest.TestCase):
    def test_bits_cross_bytes_and_signed(self):
        r=Reader(bytes([0xF5,0x37]));self.assertEqual(r.bits(4),5);self.assertEqual(r.bits(8,True),127);self.assertEqual(r.bits(4),3)
        with self.assertRaises(ValueError):r.bits(1)
        self.assertEqual(Reader(bytes([0xFC])).bits(8,True),-4)
        with self.assertRaises(ValueError):Reader(b'').bits(33)

    def triangle(self, parent=-1):
        # Version 3 textured triangle, identity bone, explicitly authored vertices.
        header=b'MB\x03\0'+struct.pack('<4H',3,1,0,1)
        vertices=struct.pack('<9h',0,0,0,10,0,0,0,10,0)
        polygon=struct.pack('<4H6B',0,0,1,2,0,0,8,0,0,8)
        bone=struct.pack('<Hh12h',3,parent,4096,0,0,0,0,4096,0,0,0,0,4096,0)
        return header+vertices+polygon+bone

    def test_geometry_and_bone_validation(self):
        m=model(self.triangle());self.assertEqual(m['polygons'][0]['indices'],[0,1,2]);self.assertEqual(m['polygons'][0]['texture'],0)
        self.assertEqual(m['vertices'],[0,0,0,10,0,0,0,10,0])
        with self.assertRaisesRegex(ValueError,'parent'):model(self.triangle(0))
        with self.assertRaises(ValueError):model(self.triangle()[:-1])

    def test_animation_interpolates_and_samples_identity(self):
        bone={'translate':[(0,[0,0,0]),(2,[4,6,8])],'rotate':[(0,[0,0,1])],'roll':[(0,[0])]}
        matrix=bone_matrix(bone,1);self.assertEqual([matrix[i] for i in (3,7,11)],[2,3,4])
        raw=b'MT\x03\0'+struct.pack('<2H',1,1)+bytes(20)+struct.pack('<HB',2,1)
        a=animation(raw);self.assertEqual(len(a[0]['matrices']),3);self.assertEqual(a[0]['matrices'][1],a[0]['matrices'][0])
        with self.assertRaises(ValueError):animation(raw[:-1])

    def test_bmp_padding_orientation_and_index_zero_alpha(self):
        raw=bytearray(70);raw[:2]=b'BM';struct.pack_into('<II',raw,10,62,40)
        struct.pack_into('<iiHHI',raw,18,2,2,1,8,0);struct.pack_into('<I',raw,46,2)
        raw[54:62]=bytes([0,0,255,0,0,255,0,0]);raw[62:70]=bytes([1,0,0,0,0,1,0,0])
        png=bitmap(raw,True);self.assertEqual(png[:8],b'\x89PNG\r\n\x1a\n')
        pos=8;compressed=b''
        while pos<len(png):
            length=struct.unpack_from('>I',png,pos)[0]
            if png[pos+4:pos+8]==b'IDAT':compressed+=png[pos+8:pos+8+length]
            pos+=12+length
        import zlib
        self.assertEqual(zlib.decompress(compressed),bytes([0,255,0,0,0,0,255,0,255,0,0,255,0,255,255,0,0,0]))
        with self.assertRaises(ValueError):bitmap(raw[:-1])

    def test_wrong_jar_rejected_before_output_created(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder);jar=root/'fake.jar';jar.write_bytes(b'not the supported profile')
            with self.assertRaisesRegex(ValueError,'Unsupported JAR'):decode(jar,root/'output')
            self.assertFalse((root/'output').exists())
            # A well-formed archive that is not a DEEP MIDlet is refused the same way.
            other=root/'other.jar'
            with zipfile.ZipFile(other,'w') as archive:
                archive.writestr('META-INF/MANIFEST.MF','MIDlet-1: Other,/icon.png,OtherMIDlet\r\n')
            with self.assertRaisesRegex(ValueError,'not a DEEP MIDlet'):decode(other,root/'output')
            self.assertFalse((root/'output').exists())

    def test_pack_is_keyed_by_the_converted_jar(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder);(root/'data').mkdir()
            for n in ('resource_registry.json','bindings.json'):(root/n).write_text('{}')
            (root/'data/tiny.txt').write_text('synthetic')
            (root/'native-data.json').write_text(json.dumps({'jar_sha256':'ab'*32}))
            with zipfile.ZipFile(io.BytesIO(pack(root))) as archive:
                self.assertEqual(json.loads(archive.read('pack.json'))['profile'],'ab'*32)
            (root/'native-data.json').write_text(json.dumps({'jar_sha256':'not a digest'}))
            with self.assertRaisesRegex(ValueError,'JAR digest'):pack(root)

    def test_pack_inventory_and_audio_required(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder);(root/'data').mkdir()
            (root/'native-data.json').write_text(json.dumps({'jar_sha256':'33'*32}))
            for n in ('resource_registry.json','bindings.json'):(root/n).write_text('{}')
            (root/'data/tiny.txt').write_text('synthetic')
            with zipfile.ZipFile(io.BytesIO(pack(root))) as archive:
                manifest=json.loads(archive.read('pack.json'))
                self.assertEqual(set(archive.namelist()),set(manifest['files'])|{'pack.json'})
                for name,record in manifest['files'].items():self.assertEqual(record['sha256'],hashlib.sha256(archive.read(name)).hexdigest())
            (root/'data/audio.mid').write_bytes(b'synthetic')
            with self.assertRaisesRegex(ValueError,'audio'):pack(root)
            (root/'data/audio.mid').unlink();(root/'data/unsafe.class').write_bytes(b'synthetic')
            with self.assertRaisesRegex(ValueError,'Non-resource'):pack(root)

if __name__=='__main__':unittest.main()
