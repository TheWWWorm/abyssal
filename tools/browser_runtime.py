"""Stage the self-hosted JAR importer with pinned, verified third-party runtimes."""
import hashlib
import json
import pathlib
import shutil
import urllib.request
import zipfile
from paths import ROOT, cache_home

SOURCES = {'micro3d.py':'browser/micro3d.py', 'import_jar.py':'browser/import_jar.py',
           'class_data.py':'tools/class_data.py', 'extract_data.py':'tools/extract_data.py'}


def stage(output, web=True):
    destination = pathlib.Path(output)/'importer'
    destination.mkdir(parents=True, exist_ok=True)
    lock = json.loads((ROOT/'browser/dependencies.json').read_text())
    cache = cache_home()/'browser-runtime'; cache.mkdir(parents=True, exist_ok=True)
    for item in lock['files']:
        source = cache/item['sha256']
        def valid(path):
            return path.is_file() and path.stat().st_size == item['bytes'] and hashlib.sha256(path.read_bytes()).hexdigest() == item['sha256']
        if not valid(source):
            print('Fetching browser runtime:', item['path'], flush=True)
            with urllib.request.urlopen(item['url'], timeout=60) as response:
                data = response.read(item['bytes']+1)
            if len(data) != item['bytes'] or hashlib.sha256(data).hexdigest() != item['sha256']:
                raise ValueError('Browser dependency checksum mismatch: '+item['path'])
            temporary = source.with_suffix('.partial'); temporary.write_bytes(data); temporary.replace(source)
        target = destination/item['path']; target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    for name in ('worker.js','audio.js'):
        shutil.copyfile(ROOT/'browser'/name, destination/name)
    if web:
        # Version this small transport independently of the Godot engine loader.
        music=(ROOT/'browser/music.js').read_bytes()
        music_name='music-'+hashlib.sha256(music).hexdigest()[:12]+'.js'
        (pathlib.Path(output)/music_name).write_bytes(music)
        page=pathlib.Path(output)/'index.html'
        page.write_text(page.read_text().replace('</head>',f'<script src="{music_name}"></script>\n</head>'))
    with zipfile.ZipFile(destination/'sources.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, source in SOURCES.items():
            info = zipfile.ZipInfo(name, date_time=(2026,9,6,0,0,0)); info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, (ROOT/source).read_bytes())
    shutil.copyfile(ROOT/'browser/dependencies.json', destination/'dependencies.json')
    return destination
