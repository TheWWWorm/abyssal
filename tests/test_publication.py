"""Publication boundary regressions; no original content fixtures."""
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from package_publication import inspect_zip, inventory, pck_entries, verify


class PublicationTests(unittest.TestCase):
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
