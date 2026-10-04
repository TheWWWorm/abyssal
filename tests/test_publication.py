"""Publication boundary regressions; no original content fixtures."""
import io
import json
import hashlib
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zipfile
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from package_publication import inspect_zip, inventory, pck_entries, verify
import package_publication


class PublicationTests(unittest.TestCase):
    def test_apk_checks_the_compatibility_converter_inventory_and_bytes(self):
        from browser_runtime import SOURCES
        from android_runtime import INDEX_HTML
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            files = {}
            for name, source in {'bootstrap.js':'android/bootstrap.js', 'import.js':'android/import.js',
                                 'audio.js':'browser/audio.js', 'worker.js':'browser/worker.js',
                                 'LICENSE.md':'LICENSE.md', 'THIRD_PARTY_NOTICES.md':'THIRD_PARTY_NOTICES.md',
                                 **{name:source for name,source in SOURCES.items()}}.items():
                path = root/source; path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'synthetic reviewed source')
                if name not in SOURCES: files[name] = path.read_bytes()
            for source, name, payload in [('browser/dependencies.json','vendor/pyodide.js',b'primary'),
                                          ('android/dependencies.json','vendor-compat/pyodide.asm.wasm',b'compatibility')]:
                path = root/source
                path.write_text(json.dumps({'files':[{'path':name,'sha256':hashlib.sha256(payload).hexdigest(),'bytes':len(payload)}]}))
                files[name] = payload
                files['android-dependencies.json' if source.startswith('android/') else 'dependencies.json'] = path.read_bytes()
            sources = io.BytesIO()
            with zipfile.ZipFile(sources,'w') as archive:
                for name, source in SOURCES.items(): archive.writestr(name,(root/source).read_bytes())
            files.update({'sources.zip':sources.getvalue(),'index.html':INDEX_HTML.encode(),'GODOT_LICENSES.txt':b'synthetic notices'})
            apk = root/'engine.apk'
            def write_apk():
                with zipfile.ZipFile(apk,'w') as archive:
                    for name, payload in files.items(): archive.writestr('assets/abyssal-importer/'+name,payload)
                    for abi in ['arm64-v8a','x86_64']: archive.writestr('lib/'+abi+'/libgodot_android.so',b'synthetic engine')
            with patch.object(package_publication,'ROOT',root):
                write_apk()
                self.assertTrue(package_publication.inspect_apk(apk,set())['offline_importer_verified'])
                files['vendor-compat/pyodide.asm.wasm'] = b'corrupt compatibility converter'
                write_apk()
                with self.assertRaisesRegex(ValueError,'checksum mismatch: vendor-compat/'):
                    package_publication.inspect_apk(apk,set())
                files['unexpected.js'] = b'unreviewed'
                write_apk()
                with self.assertRaisesRegex(ValueError,'Unexpected Android importer inventory'):
                    package_publication.inspect_apk(apk,set())

    def test_private_file_inside_nested_archive_is_rejected(self):
        inner, outer = io.BytesIO(), io.BytesIO()
        with zipfile.ZipFile(inner, 'w') as archive:
            archive.writestr('original.class', b'not an actual class')
        with zipfile.ZipFile(outer, 'w') as archive:
            archive.writestr('importer/sources.zip', inner.getvalue())
        with self.assertRaisesRegex(ValueError, 'Private content'):
            inspect_zip(outer.getvalue(), set())

    def test_game_pack_cannot_hide_an_unreviewed_asset(self):
        name = b'assets/private.png\0'
        header = b'GDPC' + struct.pack('<5I2Q', 4, 4, 7, 0, 2, 40, 40)
        directory = struct.pack('<II', 1, len(name)) + name
        directory += struct.pack('<QQ', 0, 0) + bytes(16) + struct.pack('<I', 0)
        with self.assertRaisesRegex(ValueError, 'Unreviewed resource'):
            pck_entries(header + directory, set())

    def test_nested_manifest_is_not_exempt_from_hashes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'engine').mkdir()
            (root / 'publication-manifest.json').write_text('{}')
            (root / 'engine/publication-manifest.json').write_text('extra')
            self.assertEqual(set(inventory(root)), {'engine/publication-manifest.json'})

    def test_added_or_changed_file_breaks_sealed_inventory(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'README.md').write_text('reviewed')
            record = {'files': inventory(root)}
            (root / 'publication-manifest.json').write_text(json.dumps(record))
            (root / 'README.md').write_text('changed')
            with self.assertRaisesRegex(ValueError, 'inventory changed'):
                verify(root)
            (root / 'README.md').write_text('reviewed')
            (root / 'unexpected.txt').write_text('extra')
            with self.assertRaisesRegex(ValueError, 'inventory changed'):
                verify(root)

    def test_symlink_to_private_workspace_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'shortcut').symlink_to(root.parent, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'Symbolic link'):
                inventory(root)


if __name__ == '__main__':
    unittest.main()
