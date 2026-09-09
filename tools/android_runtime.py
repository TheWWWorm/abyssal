"""Stage Godot's Android Gradle template and the offline, asset-only importer."""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import zipfile
from paths import ROOT
from browser_runtime import stage as stage_importer


INDEX_HTML = ('<!doctype html><meta charset="utf-8">'
    '<script>AbyssalNative.progress("Loading bundled converter scripts…");</script>'
    '<script src="vendor/pyodide.js"></script><script src="vendor/amrnb.js"></script>'
    '<script src="audio.js"></script><script src="import.js"></script>')


def stage(project, godot, release):
    required = ['ABYSSAL_ANDROID_KEYSTORE', 'ABYSSAL_ANDROID_KEY_ALIAS', 'ABYSSAL_ANDROID_KEY_PASSWORD']
    if release:
        missing = [name for name in required if not os.environ.get(name)]
        if missing: raise ValueError('Android release signing requires: '+', '.join(missing))
        if not pathlib.Path(os.environ[required[0]]).is_file(): raise FileNotFoundError('Android release keystore does not exist')
    version = subprocess.check_output([godot, '--version'], text=True).strip().split('.')
    status = next(i for i, part in enumerate(version) if not part.isdigit())
    template_version = '.'.join(version[:status+1])
    if os.name == 'nt':
        default = pathlib.Path(os.environ.get('APPDATA', pathlib.Path.home()/'AppData/Roaming'))/'Godot/export_templates'
    elif sys.platform == 'darwin':
        default = pathlib.Path.home()/'Library/Application Support/Godot/export_templates'
    else:
        default = pathlib.Path(os.environ.get('XDG_DATA_HOME', pathlib.Path.home()/'.local/share'))/'godot/export_templates'
    templates = pathlib.Path(os.environ.get('GODOT_TEMPLATES_PATH', default))
    source = templates/template_version/'android_source.zip'
    if not source.is_file():
        raise FileNotFoundError('Install matching Godot Android build templates: '+str(source))
    build = project/'android/build'
    build.mkdir(parents=True)
    with zipfile.ZipFile(source) as archive:
        archive.extractall(build)
    (project/'android/.build_version').write_text(template_version)
    (build/'gradlew').chmod(0o755)
    (build/'.gdignore').touch()
    gradle = build/'build.gradle'
    gradle.write_text(gradle.read_text().replace('main.res.srcDirs', "main.assets.srcDirs += ['src/importerAssets']\n        main.res.srcDirs"))
    java = build/'src/main/java/org/abyssal/engine/AbyssalImporter.java'
    java.parent.mkdir(parents=True)
    for name in ['AbyssalImporter.java', 'AbyssalImportActivity.java']:
        shutil.copyfile(ROOT/'android'/name, java.parent/name)
    manifest = build/'src/main/AndroidManifest.xml'
    text = manifest.read_text().replace('</application>',
        '<meta-data android:name="org.godotengine.plugin.v2.AbyssalImporter" '
        'android:value="org.abyssal.engine.AbyssalImporter" />\n'
        '<activity android:name="org.abyssal.engine.AbyssalImportActivity" android:exported="false" '
        'android:process=":importer" android:screenOrientation="landscape" android:hardwareAccelerated="false" '
        'android:theme="@android:style/Theme.Material.NoActionBar.Fullscreen" '
        'android:configChanges="orientation|screenSize|keyboardHidden" />\n</application>')
    manifest.write_text(text)
    assets = build/'src/importerAssets'
    importer = stage_importer(assets, web=False)
    importer.rename(assets/'abyssal-importer')
    importer = assets/'abyssal-importer'
    shutil.copyfile(ROOT/'android/import.js', importer/'import.js')
    (importer/'index.html').write_text(INDEX_HTML)
    for name in ['LICENSE.md', 'THIRD_PARTY_NOTICES.md']:
        shutil.copyfile(ROOT/name, importer/name)
    subprocess.run([godot, '--headless', '--script', str(ROOT/'tools/export_notices.gd'),
        '--', str(importer/'GODOT_LICENSES.txt')], check=True)
    # Secrets are supplied only to the disposable export preset, never public source.
    if release:
        with (project/'export_presets.cfg').open('a') as out:
            for option, variable in zip(['keystore/release', 'keystore/release_user', 'keystore/release_password'], required):
                out.write(option+'='+json.dumps(os.environ[variable])+'\n')
