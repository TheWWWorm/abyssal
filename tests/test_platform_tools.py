"""Platform boundaries use tiny, synthetic files; no original assets are committed."""
import hashlib, json, pathlib, re, sys, tempfile, unittest, zipfile
from unittest.mock import patch
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'tools'))
import pack_content, export_game
class PlatformToolsTests(unittest.TestCase):
    def test_custom_templates_do_not_enable_vendor_sdks(self):
        import package_releases
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder)
            template=root/'patched template';template.write_bytes(b'synthetic template')
            selected=package_releases.custom_templates(['linux='+str(template),'windows='+str(template),'web='+str(template)])
            self.assertEqual(selected,{'linux':template,'windows':template,'web':template})
            for platform in selected:
                stage=root/platform;stage.mkdir()
                export_game.stage_project(stage,platform,template=selected[platform])
                preset=(stage/'export_presets.cfg').read_text()
                self.assertIn('custom_template/release='+json.dumps(str(template)),preset)
                self.assertIn('renderer/rendering_method="'+('gl_compatibility' if platform=='web' else 'forward_plus')+'"',(stage/'project.godot').read_text())
                self.assertNotIn('graphics_sdk/amd',(stage/'project.godot').read_text())
            for invalid in [['android='+str(template)],['linux='+str(template)]*2,['linux='+str(root/'missing')]]:
                with self.assertRaises(ValueError):package_releases.custom_templates(invalid)

    def test_web_pack_url_changes_and_previous_build_remains_loadable(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder)
            config={'executable':'index','fileSizes':{'index.pck':3,'index.wasm':12}}
            shell=('<head>'+export_game.VIEWPORT_DEFAULT+'</head><body><script src="index.js"></script>\n'
                   'const GODOT_CONFIG = '+json.dumps(config)+';\n</body>')
            names=[]
            for payload in (b'old engine',b'updated engine'):
                (root/'index.js').write_text('synthetic loader')
                (root/'index.wasm').write_bytes(b'tiny runtime')
                (root/'index.pck').write_bytes(payload)
                (root/'index.html').write_text(shell)
                build=export_game.stamp_web_build(root)
                html=(root/'index.html').read_text()
                actual=json.loads(re.search(r'const GODOT_CONFIG = (\{[^\n]+\});',html).group(1))
                names.append(actual['mainPack'])
                self.assertEqual((root/actual['mainPack']).read_bytes(),payload)
                self.assertEqual(actual['fileSizes'][actual['mainPack']],len(payload))
                self.assertEqual(actual['fileSizes'][actual['executable']+'.wasm'],12)
                self.assertNotIn('index.pck',actual['fileSizes'])
                # The build identity is recorded invisibly, never drawn over the game.
                self.assertIn('<meta name="engine-build" content="'+hashlib.sha256(payload).hexdigest()+'">',html)
                self.assertNotIn('<div id="engine-build"',html)
                self.assertIn('src="'+actual['executable']+'.js"',html)
                # The hosted page must stay usable on a handheld browser.
                self.assertIn('viewport-fit=cover',html)
                self.assertEqual(html.count('apple-mobile-web-app-capable'),1)
                self.assertIn('overscroll-behavior: none',html)
                self.assertEqual(export_game.stamp_web_build(root),build)
                self.assertEqual((root/'index.html').read_text().count('name="engine-build"'),1)
                self.assertEqual((root/'index.html').read_text().count('rel="manifest"'),1)
                manifest=json.loads((root/'manifest.webmanifest').read_text())
                self.assertEqual([icon['sizes'] for icon in manifest['icons']],['192x192','512x512'])
                self.assertEqual((root/'index.png').read_bytes(),(export_game.ROOT/'game/ui/abyssal-splash.png').read_bytes())
            self.assertNotEqual(*names)
            self.assertEqual((root/names[0]).read_bytes(),b'old engine')

    def test_web_engine_update_changes_runtime_url_without_changing_game_pack(self):
        with tempfile.TemporaryDirectory() as folder:
            root=pathlib.Path(folder);runtimes=[];packs=[]
            for wasm in [b'old wasm',b'patched wasm']:
                (root/'index.js').write_text('synthetic loader')
                (root/'index.wasm').write_bytes(wasm)
                (root/'index.audio.worklet.js').write_text('synthetic audio')
                (root/'index.pck').write_bytes(b'unchanged game')
                config={'executable':'index','fileSizes':{'index.pck':14,'index.wasm':len(wasm)}}
                (root/'index.html').write_text('<head>'+export_game.VIEWPORT_DEFAULT+'</head><script src="index.js"></script>\nconst GODOT_CONFIG = '+json.dumps(config)+';\n')
                export_game.stamp_web_build(root)
                actual=json.loads(re.search(r'const GODOT_CONFIG = (\{[^\n]+\});',(root/'index.html').read_text()).group(1))
                runtimes.append(actual['executable']);packs.append(actual['mainPack'])
                self.assertEqual((root/(actual['executable']+'.wasm')).read_bytes(),wasm)
                self.assertTrue((root/(actual['executable']+'.audio.worklet.js')).is_file())
                self.assertFalse((root/'index.wasm').exists())
                self.assertEqual(actual['fileSizes'][actual['executable']+'.wasm'],len(wasm))
            self.assertNotEqual(*runtimes)
            self.assertEqual(*packs)
            self.assertEqual((root/(runtimes[0]+'.wasm')).read_bytes(),b'old wasm')

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
                # Desktop x86-64 keeps Forward+ with the OpenGL fallback; everything else exports on OpenGL.
                settings=(stage/'project.godot').read_text()
                if platform in {'linux','windows'}:
                    self.assertIn('renderer/rendering_method="forward_plus"',settings);self.assertIn('fallback_to_opengl3=true',settings)
                else:self.assertNotIn('forward_plus',settings)
                self.assertFalse(any(p.suffix in {'.jar','.wav','.abyss'} for p in stage.rglob('*')))
                self.assertEqual(sorted(p.relative_to(stage).as_posix() for p in stage.rglob('*.png')),['ui/abyssal-icon.png','ui/abyssal-splash.png'])
                for name in ['abyssal-icon.ico','abyssal-icon.icns']:
                    self.assertTrue((stage/'ui'/name).is_file())
                self.assertIn('boot_splash/image="res://ui/abyssal-splash.png"',settings)
            self.assertIn('variant/thread_support=false',(pathlib.Path(folder)/'web/export_presets.cfg').read_text())
            for platform,architecture in [('linux','x86_64'),('linux-arm64','arm64')]:
                preset=(pathlib.Path(folder)/platform/'export_presets.cfg').read_text()
                self.assertIn('platform="Linux"',preset)
                self.assertIn('binary_format/architecture="'+architecture+'"',preset)
                self.assertEqual(export_game.PLATFORMS[platform][1],'abyssal.'+architecture)
            self.assertIn('texture_format/etc2_astc=true',(pathlib.Path(folder)/'linux-arm64/export_presets.cfg').read_text())
            android=(pathlib.Path(folder)/'android/export_presets.cfg').read_text()
            for option in ['permissions/internet=false','permissions/manage_external_storage=false','permissions/vibrate=true',
                           'architectures/arm64-v8a=true','architectures/x86_64=true',
                           'gradle_build/use_gradle_build=true','launcher_icons/adaptive_monochrome_432x432="res://ui/abyssal-monochrome.svg"']:
                self.assertIn(option,android)
            stage=pathlib.Path(folder)/'versioned';stage.mkdir()
            export_game.stage_project(stage,'android','0.2.0',17)
            self.assertIn('version/code=17',(stage/'export_presets.cfg').read_text())
            self.assertIn('version/name="0.2.0"',(stage/'export_presets.cfg').read_text())
if __name__=='__main__':unittest.main()
