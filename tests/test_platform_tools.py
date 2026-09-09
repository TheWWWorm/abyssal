"""Platform boundaries use tiny, synthetic files; no original assets are committed."""
import hashlib, json, pathlib, re, sys, tempfile, unittest, zipfile
from unittest.mock import patch
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'tools'))
import pack_content, export_game
class PlatformToolsTests(unittest.TestCase):
    def test_web_pack_url_changes_and_previous_build_remains_loadable(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder)
            (root/'index.js').write_text('synthetic loader')
            config={'executable':'index','fileSizes':{'index.pck':3,'index.wasm':12}}
            shell=('<head>'+export_game.VIEWPORT_DEFAULT+'</head><body><script src="index.js"></script>\n'
                   'const GODOT_CONFIG = '+json.dumps(config)+';\n</body>')
            names=[]
            for payload in (b'old engine',b'updated engine'):
                (root/'index.pck').write_bytes(payload)
                (root/'index.html').write_text(shell)
                build=export_game.stamp_web_build(root)
                html=(root/'index.html').read_text()
                actual=json.loads(re.search(r'const GODOT_CONFIG = (\{[^\n]+\});',html).group(1))
                names.append(actual['mainPack'])
                self.assertEqual((root/actual['mainPack']).read_bytes(),payload)
                self.assertEqual(actual['fileSizes'][actual['mainPack']],len(payload))
                self.assertEqual(actual['fileSizes']['index.wasm'],12)
                self.assertNotIn('index.pck',actual['fileSizes'])
                # The build identity is recorded invisibly, never drawn over the game.
                self.assertIn('<meta name="engine-build" content="'+hashlib.sha256(payload).hexdigest()+'">',html)
                self.assertNotIn('<div id="engine-build"',html)
                self.assertIn('src="index.js?v=',html)
                # The hosted page must stay usable on a handheld browser.
                self.assertIn('viewport-fit=cover',html)
                self.assertEqual(html.count('apple-mobile-web-app-capable'),1)
                self.assertIn('overscroll-behavior: none',html)
                self.assertEqual(export_game.stamp_web_build(root),build)
                self.assertEqual((root/'index.html').read_text().count('name="engine-build"'),1)
            self.assertNotEqual(*names)
            self.assertEqual((root/names[0]).read_bytes(),b'old engine')

    def fixture(self, cache):
        cache.mkdir();(cache/'data').mkdir()
        (cache/'native-data.json').write_text(json.dumps({'jar_sha256':'11'*32,'importer':'native-6'}))
        (cache/'resource_registry.json').write_text('[]');(cache/'bindings.json').write_text('{}');(cache/'data/tiny.txt').write_text('synthetic')
    def test_pack_has_complete_hash_inventory_and_no_tool_cache(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder);cache=root/'cache';self.fixture(cache)
            (cache/'engine-import.json').write_text('private converter metadata')
            output=root/'private.abyss';pack_content.pack(cache,output)
            with zipfile.ZipFile(output) as archive:
                manifest=json.loads(archive.read('pack.json'))
                self.assertEqual(set(archive.namelist()),set(manifest['files'])|{'pack.json'})
                self.assertNotIn('engine-import.json',archive.namelist())
                self.assertEqual(manifest['files']['data/tiny.txt']['size'],9)
    def test_pack_rejects_executable_or_symlink(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder);cache=root/'cache';self.fixture(cache)
            (cache/'data/bad.gd').write_text('extends Node')
            with self.assertRaisesRegex(ValueError,'Executable'):pack_content.pack(cache,root/'private.abyss')
            (cache/'data/bad.gd').unlink();(cache/'data/linked.txt').symlink_to(cache/'native-data.json')
            with self.assertRaisesRegex(ValueError,'Symlinks'):pack_content.pack(cache,root/'private.abyss')
    def test_export_stages_only_manifest_runtime_for_every_platform(self):
        with tempfile.TemporaryDirectory() as folder:
            for platform in export_game.PLATFORMS:
                stage=pathlib.Path(folder)/platform;stage.mkdir();export_game.stage_project(stage,platform)
                self.assertTrue((stage/'project.godot').is_file())
                self.assertFalse((stage/'tools').exists())
                self.assertFalse((stage/'data').exists())
                self.assertNotIn('forward_plus',(stage/'project.godot').read_text())
                self.assertFalse(any(p.suffix in {'.jar','.wav','.png','.abyss'} for p in stage.rglob('*')))
            self.assertIn('variant/thread_support=false',(pathlib.Path(folder)/'web/export_presets.cfg').read_text())
            android=(pathlib.Path(folder)/'android/export_presets.cfg').read_text()
            for option in ['permissions/internet=false','permissions/manage_external_storage=false',
                           'architectures/arm64-v8a=true','architectures/x86_64=true',
                           'gradle_build/use_gradle_build=true']:
                self.assertIn(option,android)
            stage=pathlib.Path(folder)/'versioned';stage.mkdir()
            export_game.stage_project(stage,'android','0.2.0',17)
            self.assertIn('version/code=17',(stage/'export_presets.cfg').read_text())
            self.assertIn('version/name="0.2.0"',(stage/'export_presets.cfg').read_text())
if __name__=='__main__':unittest.main()
