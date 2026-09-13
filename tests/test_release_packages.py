"""Release containers use synthetic binaries and never embed game fixtures."""
import io,json,pathlib,struct,sys,tempfile,unittest,tarfile,zipfile
from unittest.mock import patch
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'tools'))
from package_releases import archive_build
from desktop_runtime import embed_macos
import desktop_runtime

def synthetic_universal(intel,arm):
    """Build a minimal Mach-O universal binary carrying an x86_64 and an arm64 slice."""
    header=8+2*20;first=header;second=first+len(intel)
    blob=struct.pack('>II',0xCAFEBABE,2)
    blob+=struct.pack('>iiIII',0x01000007,3,first,len(intel),0)
    blob+=struct.pack('>iiIII',0x0100000C,0,second,len(arm),0)
    return blob+intel+arm



class ReleaseTests(unittest.TestCase):
    def test_linux_preserves_launcher_and_runtime_permissions(self):
        with tempfile.TemporaryDirectory() as temp:
            root=pathlib.Path(temp)
            for platform,architecture in [('linux','x86_64'),('linux-arm64','arm64')]:
                with self.subTest(platform=platform):
                    stage=root/platform;stage.mkdir()
                    exe=stage/('abyssal.'+architecture);exe.write_bytes(b'synthetic');exe.chmod(0o755)
                    runtime=stage/'importer/bin'/platform/'node';runtime.parent.mkdir(parents=True);runtime.write_bytes(b'synthetic runtime');runtime.chmod(0o755)
                    archive_build(stage,root/'release.tar.gz',platform)
                    with tarfile.open(root/'release.tar.gz') as archive:
                        self.assertEqual(set(archive.getnames()),{'AbyssalEngine/'+p.relative_to(stage).as_posix() for p in [exe,runtime]})
                        for entry in archive.getmembers():self.assertTrue(entry.mode&0o111)
    def test_linux_stages_only_matching_offline_runtime(self):
        records=json.loads((desktop_runtime.ROOT/'desktop/dependencies.json').read_text())['files']
        with tempfile.TemporaryDirectory() as temp:
            root=pathlib.Path(temp)
            for platform in ['linux','linux-arm64']:
                with self.subTest(platform=platform):
                    record=next(r for r in records if r['platform']==platform)
                    bundle=root/(platform+'.tar.xz')
                    payload=('synthetic '+platform).encode()
                    with tarfile.open(bundle,'w:xz') as archive:
                        for name,data in [(record['member'],payload),(record['license_member'],b'synthetic license')]:
                            info=tarfile.TarInfo(name);info.size=len(data);archive.addfile(info,io.BytesIO(data))
                    output=root/platform;importer=output/'importer';(importer/'licenses').mkdir(parents=True)
                    with patch.object(desktop_runtime,'stage_importer',return_value=importer),patch.object(desktop_runtime,'fetch',return_value=bundle) as fetch:
                        desktop_runtime.stage(output,platform)
                    fetch.assert_called_once_with(record)
                    self.assertEqual(list((importer/'bin').iterdir()),[importer/'bin'/platform])
                    executable=importer/'bin'/platform/'node'
                    self.assertEqual(executable.read_bytes(),payload)
                    self.assertTrue(executable.stat().st_mode&0o111)
                    self.assertEqual((importer/'licenses/Node.txt').read_bytes(),b'synthetic license')
    def test_macos_embeds_arm64_runtime_and_unnests_app(self):
        with tempfile.TemporaryDirectory() as temp:
            root=pathlib.Path(temp);stage=root/'build';stage.mkdir()
            with zipfile.ZipFile(stage/'abyssal.zip','w') as archive:archive.writestr('abyssal.app/Contents/MacOS/abyssal',synthetic_universal(b'intel slice',b'apple silicon slice'))
            for cpu in ['macos-arm64']:
                exe=stage/'importer/bin'/cpu/'node';exe.parent.mkdir(parents=True);exe.write_bytes(b'synthetic runtime');exe.chmod(0o755)
            embed_macos(stage);self.assertFalse((stage/'importer').exists())
            with zipfile.ZipFile(stage/'abyssal.zip') as archive:
                self.assertEqual(archive.read('abyssal.app/Contents/MacOS/abyssal'),b'apple silicon slice')
            archive_build(stage,root/'release.zip','macos')
            with zipfile.ZipFile(root/'release.zip') as archive:
                self.assertNotIn('abyssal.zip',archive.namelist())
                for cpu in ['macos-arm64']:
                    info=archive.getinfo('abyssal.app/Contents/Resources/importer/bin/'+cpu+'/node');self.assertTrue(info.external_attr>>16&0o111)
    def test_rejects_private_content_and_links(self):
        with tempfile.TemporaryDirectory() as temp:
            root=pathlib.Path(temp);stage=root/'build';stage.mkdir()
            for suffix in ['jar','abyss','class']:
                private=stage/('private.'+suffix);private.write_bytes(b'synthetic')
                with self.assertRaises(ValueError):archive_build(stage,root/'release.zip','windows')
                private.unlink()
            (stage/'link').symlink_to(root)
            with self.assertRaises(ValueError):archive_build(stage,root/'release.zip','windows')
if __name__=='__main__':unittest.main()
