"""Release-boundary checks use synthetic content only."""
import hashlib, json, pathlib, sys, tempfile, unittest, zipfile
from unittest.mock import patch
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'tools'))
import import_native as importer
import package_source as packaging
import audit_provenance as provenance

class DistributionTests(unittest.TestCase):
    def test_unsupported_archive_never_starts_java(self):
        with tempfile.TemporaryDirectory() as temporary:
            jar=pathlib.Path(temporary)/'untrusted.jar';jar.write_bytes(b'not a MIDlet archive')
            with patch.object(importer,'build') as build:
                with self.assertRaisesRegex(ValueError,'Unsupported JAR'):importer.prepare(jar)
                build.assert_not_called()
    def test_other_deep_builds_reach_conversion(self):
        # Acceptance is structural: a DEEP MIDlet other than the developed-against
        # build is imported, and conversion decides whether its layout matches.
        with tempfile.TemporaryDirectory() as temporary:
            jar=pathlib.Path(temporary)/'other-build.jar'
            with zipfile.ZipFile(jar,'w') as archive:
                archive.writestr('META-INF/MANIFEST.MF','Manifest-Version: 1.0\r\nMIDlet-1: Deep,/data/interface/icon.png,DeepMIDlet\r\n')
            self.assertTrue(importer.deep_midlet(jar))
            self.assertNotEqual(importer.file_hash(jar),importer.VERIFIED)
            with patch.object(importer,'build',side_effect=RuntimeError('reached conversion')) as build:
                with self.assertRaisesRegex(RuntimeError,'reached conversion'):importer.prepare(jar)
                build.assert_called_once()

    def test_cache_checks_every_published_resource(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary)
            files={'native-data.json':b'{}','resource_registry.json':b'[]','data/test.txt':b'local test content'}
            for name,data in files.items():
                path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
            stamp={'version':importer.VERSION,'jar_sha256':'22'*32,'converter':'test-converter','files':{name:hashlib.sha256(data).hexdigest() for name,data in files.items()}}
            (root/'engine-import.json').write_text(json.dumps(stamp))
            with patch.object(importer,'importer_hash',return_value='test-converter'):
                self.assertTrue(importer.valid_cache(root,'22'*32))
                (root/'data/test.txt').write_bytes(b'corrupted')
                self.assertFalse(importer.valid_cache(root,'22'*32))
                (root/'data/test.txt').write_bytes(files['data/test.txt'])
                (root/'resource_registry.json').unlink()
                self.assertFalse(importer.valid_cache(root,'22'*32))
    def test_package_has_only_reviewed_source(self):
        files=packaging.source_files()
        self.assertTrue(files)
        for path in files:
            self.assertNotIn(path.suffix,{'.jar','.png','.glb','.wav','.class','.mbac','.mtra'})
        source='\n'.join(p.read_text() for p in files if p.suffix=='.gd')
        self.assertNotIn('res://art/',source)
        self.assertNotIn('res://../',source)
    def test_unlisted_asset_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary);(root/'README.md').write_text('test source')
            manifest=root/'source-manifest.json';manifest.write_text(json.dumps({'files':['README.md']}))
            (root/'accidental.png').write_bytes(b'\x89PNG')
            with patch.object(packaging,'ROOT',root),patch.object(packaging,'MANIFEST',manifest):
                with self.assertRaisesRegex(ValueError,'Unreviewed files'):packaging.source_files()
    def test_disguised_binary_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary);(root/'fixture.json').write_bytes(b'PK\x03\x04binary')
            manifest=root/'source-manifest.json';manifest.write_text(json.dumps({'files':['fixture.json']}))
            with patch.object(packaging,'ROOT',root),patch.object(packaging,'MANIFEST',manifest):
                with self.assertRaisesRegex(ValueError,'Binary payload'):packaging.source_files()
    def test_extracted_archive_can_be_verified_and_repacked(self):
        import zipfile
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary)
            packaging.package(root/'source.zip')
            with zipfile.ZipFile(root/'source.zip') as archive:archive.extractall(root/'unpacked')
            extracted=root/'unpacked/abyssal-engine'
            with patch.object(packaging,'ROOT',extracted),patch.object(packaging,'MANIFEST',extracted/'source-manifest.json'):
                packaging.package(root/'repacked.zip')
                (extracted/'README.md').write_text('unexpected edit')
                with self.assertRaisesRegex(ValueError,'checksums differ'):packaging.source_files()

    def test_changed_reviewed_source_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary);(root/'provenance').mkdir()
            (root/'example.gd').write_text('extends RefCounted\n')
            (root/'source-manifest.json').write_text(json.dumps({'files':['example.gd']}))
            report={'legal_status':'not cleared','files':[{'path':'example.gd','sha256':provenance.digest(root/'example.gd'),'origin':'synthetic test','basis':'independent test fixture'}]}
            (root/'provenance/source-provenance.json').write_text(json.dumps(report))
            self.assertEqual(provenance.verify(root)['reviewed_source_files'],1)
            (root/'example.gd').write_text('unexpected code')
            with self.assertRaisesRegex(ValueError,'changed since'):provenance.verify(root)

    def test_runtime_boundary_holds_without_a_local_review(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=pathlib.Path(temporary);(root/'runtime/java/bridge').mkdir(parents=True)
            source=root/'runtime/java/bridge/Assets.java';source.write_text('class Assets {}\n')
            (root/'source-manifest.json').write_text(json.dumps({'files':['runtime/java/bridge/Assets.java']}))
            # The review record is local-only, so packaged source verifies without it.
            self.assertEqual(provenance.verify(root)['local_review'],False)
            source.write_text('class Assets { Class.forName("Deep"); }\n')
            with self.assertRaisesRegex(ValueError,'runtime dependency'):provenance.verify(root)

if __name__=='__main__':unittest.main()
