"""Synthetic portable decoder and pack boundary regressions; no game fixtures."""
import hashlib, io, json, pathlib, shutil, struct, subprocess, sys, tempfile, unittest, zipfile
sys.path[:0] = [str(pathlib.Path(__file__).resolve().parents[1]/p) for p in ('browser','tools')]
from micro3d import Reader, model, animation, bone_matrix
from import_jar import ENLARGE, bitmap, convert_m3g, decode, emblem_patterns, enlarge_stunted, pack, png, png_texels, read_entry, translucence
import m3g
from extract_data import has_converted_resource, language_strings, midlet_version
from class_data import DataError

class LanguageDataTests(unittest.TestCase):
    def setUp(self):
        self.temporary=tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.language=pathlib.Path(self.temporary.name)/'ru'
        self.language.mkdir()
        # Small, synthetic slot tables; no fixed game-version counts.
        self.constants={f'{field}:[Ljava.lang.String;':[None]*count
                        for field,count in zip('abcde',(2,1,1,1,1))}
        self.constants.update({'a:[I':[1,2],'g:[S':[0,0,0]})
        self.groups=[('main',['Привет','']),('ships',['Ship']),('cargo',['Cargo']),
                     ('items',['Item']),('medals',['Medal']),('0',['First']),('1',['Second','Last'])]
        for name,words in self.groups:
            (self.language/f'{name}.lang').write_bytes(self.records(words))

    @staticmethod
    def records(words):
        return b''.join(struct.pack('>H',len(raw))+raw for raw in (word.encode('utf-8') for word in words))

    def test_declared_slots_ignore_trailing_bytes_without_shifting_ids(self):
        expected=[word for _,words in self.groups for word in words]
        for name,_ in self.groups:
            path=self.language/f'{name}.lang';original=path.read_bytes()
            for tail in (b'\xb8 #.',b'\x00',self.records(['Unused extra text'])):
                with self.subTest(file=name,tail=tail):
                    path.write_bytes(original+tail)
                    self.assertEqual(language_strings(self.language,self.constants),expected)
            path.write_bytes(original)

    def test_counts_follow_the_selected_build(self):
        self.constants['a:[Ljava.lang.String;']=[None]
        self.constants['a:[I']=[1,1]
        expected=['Привет','Ship','Cargo','Item','Medal','First','Second']
        self.assertEqual(language_strings(self.language,self.constants),expected)

    def test_required_records_still_reject_truncation_and_bad_text(self):
        first=self.records(['Привет'])
        for broken in (b'',b'\x00',b'\x00\x04abc',b'\x00\x01\xff'):
            with self.subTest(record=broken):
                (self.language/'main.lang').write_bytes(first+broken)
                with self.assertRaisesRegex(DataError,r'ru/main\.lang \(string 2 of 2, byte 14\)'):
                    language_strings(self.language,self.constants)

    def test_modified_utf8_preserves_nul_and_supplementary_characters(self):
        raw=b'\xc0\x80\xed\xa0\xbd\xed\xba\x80'
        (self.language/'main.lang').write_bytes(struct.pack('>H',len(raw))+raw+b'\0\0')
        self.assertEqual(language_strings(self.language,self.constants)[:2],['\0🚀',''])

    def test_chapter_counts_must_cover_the_campaign(self):
        self.constants['a:[I'].pop()
        with self.assertRaisesRegex(DataError,'chapter language counts'):
            language_strings(self.language,self.constants)

class BrowserImportTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('node'), 'Node.js is needed for browser picker checks')
    def test_web_picker_lifecycle(self):
        result=subprocess.run([shutil.which('node'),str(pathlib.Path(__file__).with_name('browser_file_check.js'))],
                              capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_registered_bmp_uses_converted_png(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder)
            texture=root/'data/textures/fx.bmp.png'
            texture.parent.mkdir(parents=True)
            texture.write_bytes(b'converted image')
            self.assertTrue(has_converted_resource(root,'data/textures/fx.bmp'))
            self.assertFalse(has_converted_resource(root,'data/textures/missing.bmp'))
            self.assertFalse(has_converted_resource(root,'data/v3d/missing.mbac'))
            texture.with_suffix('').write_bytes(b'original bitmap')
            texture.unlink()
            self.assertTrue(has_converted_resource(root,'data/textures/fx.bmp'))

    def test_midlet_version_names_the_build(self):
        def jar(manifest):
            data=io.BytesIO()
            with zipfile.ZipFile(data,'w') as archive:
                if manifest is not None:archive.writestr('META-INF/MANIFEST.MF',manifest)
            return zipfile.ZipFile(data)
        self.assertEqual(midlet_version(jar('MIDlet-Name: Deep\r\nMIDlet-Version: 1.0.2\r\n')),'1.0.2')
        self.assertEqual(midlet_version(jar('MIDlet-Name: Deep\n')),'')
        self.assertEqual(midlet_version(jar('MIDlet-Version: <b>1</b>\n')),'')
        self.assertEqual(midlet_version(jar(None)),'')

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

    def test_short_deflate_entry_is_salvaged_by_size_and_crc(self):
        # A repacked copy of the game's JAR ends one byte early: its last entry's
        # deflate stream stops before the end-of-block marker, on top of the next
        # local header. Both java.util.zip and zipfile refuse it although every
        # byte of the payload is present. Recover it, and refuse a real loss.
        import zlib
        payload=bytes(range(256))*20
        # Stored blocks, closed by a separate final empty block, so that the last
        # byte carries only the end-of-stream marker, as in the damaged copy.
        packer=zlib.compressobj(0,zlib.DEFLATED,-15);stream=packer.compress(payload)+packer.flush(zlib.Z_SYNC_FLUSH)+packer.flush()
        manifest=b'MIDlet-1: Deep,/data/interface/icon.png,DeepMIDlet\r\n'
        def local(name,data,crc,csize,usize,method):
            return struct.pack('<IHHHHHIIIHH',0x04034b50,20,0,method,0,0,crc,csize,usize,len(name),0)+name+data
        def central(name,crc,csize,usize,method,offset):
            return struct.pack('<IHHHHHHIIIHHHHHII',0x02014b50,20,20,0,method,0,0,crc,csize,usize,len(name),0,0,0,0,0,offset)+name
        def assemble(short_by):
            # The directory claims the whole stream; the file holds short_by bytes less of it.
            first=local(b'data/v3d/last.mbac',stream[:len(stream)-short_by],zlib.crc32(payload),len(stream),len(payload),8)
            second=local(b'META-INF/MANIFEST.MF',manifest,zlib.crc32(manifest),len(manifest),len(manifest),0)
            directory=central(b'data/v3d/last.mbac',zlib.crc32(payload),len(stream),len(payload),8,0)+central(b'META-INF/MANIFEST.MF',zlib.crc32(manifest),len(manifest),len(manifest),0,len(first))
            return first+second+directory+struct.pack('<IHHHHIIH',0x06054b50,0,0,2,2,len(directory),len(first)+len(second),0)
        with tempfile.TemporaryDirectory() as folder:
            jar=pathlib.Path(folder)/'short.jar'
            jar.write_bytes(assemble(0))
            with zipfile.ZipFile(jar) as archive:self.assertEqual(read_entry(archive,archive.getinfo('data/v3d/last.mbac')),payload)
            jar.write_bytes(assemble(1))
            with zipfile.ZipFile(jar) as archive:
                self.assertEqual(read_entry(archive,archive.getinfo('data/v3d/last.mbac')),payload)
                self.assertEqual(read_entry(archive,archive.getinfo('META-INF/MANIFEST.MF')),manifest)
            # Cut into the payload itself and the entry is genuinely lost.
            jar.write_bytes(assemble(40))
            with zipfile.ZipFile(jar) as archive:
                with self.assertRaisesRegex(ValueError,'Damaged JAR entry'):read_entry(archive,archive.getinfo('data/v3d/last.mbac'))
            # The whole conversion accepts the one-byte-short archive.
            jar.write_bytes(assemble(1))
            with self.assertRaises(Exception) as outcome:decode(jar,pathlib.Path(folder)/'output')
            self.assertNotIn('Damaged JAR entry',str(outcome.exception))

    def test_malformed_m3g_is_refused(self):
        for data in (b'JSR184',m3g.IDENTIFIER+b'\x00\xff\xff\xff\x7f'):
            with self.subTest(data=data),self.assertRaises(ValueError):m3g.model(data)

    @staticmethod
    def synthetic_m3g():
        """A static emblem mesh, and an upright-turned group whose translucent
        mesh slides along Z over two frames."""
        def obj(kind,body):return struct.pack('<BI',kind,len(body))+body
        plain=struct.pack('<III',0,0,0)
        def node(extra=b'',tracks=()):
            moved=struct.pack('<B3f3ff3f',1,*extra) if extra else b'\x00'
            return struct.pack('<II',0,len(tracks))+b''.join(struct.pack('<I',t) for t in tracks)+struct.pack('<I',0)+moved+b'\x00'+b'\x01\x01\xff'+struct.pack('<I',0xffffffff)+b'\x00'
        def array(size,rows):
            fmt='<'+('b' if size==1 else 'h')*len(rows[0])
            return obj(20,plain+struct.pack('<BBBH',size,len(rows[0]),0,len(rows))+b''.join(struct.pack(fmt,*r) for r in rows))
        def material(rgb):return obj(13,plain+bytes(10)+bytes(rgb)+struct.pack('<f',1)+b'\x00')
        texture=obj(17,plain+b'\x00\x00'+struct.pack('<I',0)+bytes(3)+bytes([228,241,241,208,210]))
        def appearance(material_ref,texture_ref):return obj(3,plain+b'\x00'+struct.pack('<IIIIII',0,0,0,material_ref,1,texture_ref))
        quad=[[0,0,0],[100,0,0],[0,100,0],[100,100,0]]
        objects=[obj(0,b'\x01\x00\x00'+struct.pack('<II',0,0)+b'\x00'),   # 1 header
            array(2,quad),array(1,[[0,0,127]]*4),array(2,[[16,0],[32,0],[16,16],[32,16]]),   # 2-4
            obj(21,plain+bytes(4)+struct.pack('<I3ffII',2,0,0,0,1,3,0)+struct.pack('<II3ff',1,4,0,0,0,1/128)),   # 5
            obj(11,plain+b'\x80'+struct.pack('<5I',4,0,1,2,3)+struct.pack('<II',1,4)),   # 6 one strip
            material((255,0,0)),texture,appearance(7,8),   # 7-9 emblem
            obj(14,node()+struct.pack('<III',5,1,6)+struct.pack('<I',9)),   # 10
            obj(9,node()+struct.pack('<II',1,10)),   # 11 still group
            obj(19,plain+bytes([176,192,0])+struct.pack('<IIIII',2,0,1,3,2)+struct.pack('<I3f',0,0,0,4)+struct.pack('<I3f',2,0,0,6)),   # 12
            obj(1,plain+struct.pack('<ffiifi',1,1,0,0,0,0)),obj(2,plain+struct.pack('<III',12,13,275)),   # 13-14
            material((0,255,0)),texture,appearance(15,16),   # 15-17 translucent
            obj(14,node((0,0,4,1,1,1,0,1,0,0),tracks=(14,))+struct.pack('<III',5,1,6)+struct.pack('<I',17)),   # 18
            obj(9,node((0,0,0,1,1,1,90,1,0,0))+struct.pack('<II',1,18))]   # 19 upright group
        body=b''.join(objects);section=struct.pack('<BII',0,len(body)+13,len(body))+body
        return m3g.IDENTIFIER+section+struct.pack('<I',__import__('zlib').adler32(section))

    def test_m3g_placeholder_mesh_reads_as_an_empty_model(self):
        # The low-detail build stands in a mesh with no vertex buffer for some models.
        def obj(kind,body):return struct.pack('<BI',kind,len(body))+body
        node=struct.pack('<III',0,0,0)+b'\x00\x00\x01\x01\xff'+struct.pack('<I',0xffffffff)+b'\x00'
        body=(obj(0,b'\x01\x00\x00'+struct.pack('<II',0,0)+b'\x00')+obj(14,node+struct.pack('<II',0,0))
              +obj(9,node+struct.pack('<II',1,2)))
        section=struct.pack('<BII',0,len(body)+13,len(body))+body
        shape,frames=m3g.model(m3g.IDENTIFIER+section+struct.pack('<I',__import__('zlib').adler32(section)))
        self.assertEqual((shape['vertices'],shape['polygons'],frames),([],[],[]))
        self.assertEqual([b['vertices'] for b in shape['bones']],[0])

    def test_m3g_key_sharing_a_time_with_a_later_one_is_superseded(self):
        sequence={'valid':[0,3],'interpolation':176,'keys':[(0,[90.0,-1.0,0.0]),(0,[1.0,1.0,1.0]),(1,[0.0,0.0,0.0]),(5,[1.0,1.0,1.0])]}
        controller={'sequence_time':0.0,'speed':1.0,'world_time':0}
        self.assertEqual(m3g.sample(sequence,controller,0),[1.0,1.0,1.0])
        self.assertEqual(m3g.sample(sequence,controller,3),[0.5,0.5,0.5])

    def test_m3g_parts_read_as_mascot_capsule_model_data(self):
        shape,frames=m3g.model(self.synthetic_m3g())
        self.assertEqual([(b['vertices'],b['parent']) for b in shape['bones']],[(4,-1),(4,-1)])
        # The upright turn of the exporter's root group is not applied.
        self.assertEqual([round(v,6) for v in shape['bones'][1]['matrix']],[1,0,0,0,0,1,0,0,0,0,1,4])
        emblem=[p for p in shape['polygons'] if p['pattern']]
        self.assertEqual(sorted({p['pattern'] for p in emblem}),[2,4,8])
        first=next(p for p in emblem if p['pattern']==2)
        # Strip faces are listed the other way round, and texels counted from their centres.
        self.assertEqual(first['indices'],[1,0,2])
        self.assertEqual(first['attributes'][:2],[31.5,-0.5])
        second=next(p for p in emblem if p['pattern']==4 and p['indices']==first['indices'])
        self.assertEqual(second['attributes'][1],15.5)
        glow=[p for p in shape['polygons'] if p['blend']]
        self.assertEqual({(p['blend'],p['double_sided']) for p in glow},{(4,True)})
        self.assertEqual(shape['patterns'],4)
        # Each frame is applied after the rest pose: half way, one unit along Z.
        self.assertEqual(frames[0]['last_frame'],2)
        self.assertAlmostEqual(frames[0]['matrices'][1][12+11],1.0)
        self.assertAlmostEqual(frames[0]['matrices'][0][11],0.0)

    def test_stunted_m3g_model_is_enlarged_with_its_offsets(self):
        bone = {'vertices': 2, 'parent': -1, 'matrix': [1, 0, 0, 5, 0, 1, 0, 0, 0, 0, 1, -2]}
        shape = {'vertices': [0, 0, 0, 10, 4, -3], 'bones': [bone]}
        frames = [{'matrices': [[1, 0, 0, 1, 0, 1, 0, 2, 0, 0, 1, 3]]}]
        enlarge_stunted(shape, frames)
        self.assertEqual(shape['vertices'], [0, 0, 0, 10*ENLARGE, 4*ENLARGE, -3*ENLARGE])
        self.assertEqual(bone['matrix'], [1, 0, 0, 5*ENLARGE, 0, 1, 0, 0, 0, 0, 1, -2*ENLARGE])
        self.assertEqual(frames[0]['matrices'][0], [1, 0, 0, ENLARGE, 0, 1, 0, 2*ENLARGE, 0, 0, 1, 3*ENLARGE])
        crate = {'vertices': [0, 0, 0, 216, 100, 100], 'bones': []}
        enlarge_stunted(crate, []); enlarge_stunted({'vertices': [], 'bones': []}, [])
        self.assertEqual(crate['vertices'], [0, 0, 0, 216, 100, 100])

    def test_dithered_atlas_alpha_is_recovered(self):
        # Half the texels solid in a checkerboard reads as about half alpha;
        # an atlas that has partial alpha is read as it is.
        dithered=bytes(v for y in range(4) for x in range(4) for v in (9,9,9,255 if (x+y)%2 else 0))
        self.assertTrue(all(113<=a<=142 for a in translucence(4,4,dithered)[5:7]))
        partial=bytes([9,9,9,128])*16
        self.assertEqual(translucence(4,4,partial),bytes([128])*16)

    def test_m3g_conversion_writes_models_atlas_and_emblem_frames(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder);(root/'data/3d').mkdir(parents=True);(root/'data/textures').mkdir()
            (root/'data/3d/u4.m3g').write_bytes(self.synthetic_m3g())
            rows=b''.join(b'\x00'+bytes([200,100,50,64])*128 for _ in range(128))
            (root/'data/textures/deep.png').write_bytes(png(128,128,rows))
            self.assertEqual(convert_m3g(root,[{'id':4,'model':'data/3d/u4.mbac','textures':['data/textures/deep.bmp']}]),['data/3d/u4.mbac'])
            self.assertTrue(has_converted_resource(root,'data/3d/u4.mbac'))
            frames=json.loads((root/'data/3d/u4.mtra.json').read_text())
            self.assertEqual((frames[0]['patterns'],frames[0]['last_frame']),emblem_patterns(4))
            self.assertEqual(emblem_patterns(4),({'0':2,'3':4,'6':8},8))
            self.assertEqual(len(frames[0]['matrices']),9)
            width,height,texels=png_texels((root/'data/textures/deep.bmp.png').read_bytes())
            # Texels the glow samples add only their own light; the others keep their colour.
            self.assertEqual(texels[(5*128+20)*4:(5*128+20)*4+4],bytes([50,25,12,64]))
            self.assertEqual(texels[(100*128+100)*4:(100*128+100)*4+4],bytes([200,100,50,64]))

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
