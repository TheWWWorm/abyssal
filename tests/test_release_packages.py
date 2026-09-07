"""Release containers use synthetic binaries and never embed game fixtures."""
import pathlib,struct,sys,tempfile,unittest,tarfile,zipfile
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'tools'))
from package_releases import archive_build
from desktop_runtime import embed_macos

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
            root=pathlib.Path(temp);stage=root/'build';stage.mkdir()
            exe=stage/'abyssal.x86_64';exe.write_bytes(b'synthetic');exe.chmod(0o755)
            runtime=stage/'importer/bin/linux/node';runtime.parent.mkdir(parents=True);runtime.write_bytes(b'synthetic runtime');runtime.chmod(0o755)
            archive_build(stage,root/'release.tar.gz','linux')
            with tarfile.open(root/'release.tar.gz') as archive:
                for entry in archive.getmembers():self.assertTrue(entry.mode&0o111)
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
