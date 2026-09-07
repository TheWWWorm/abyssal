#!/usr/bin/env python3
"""Decode resources and audio from the selected local JAR."""
import json, os, pathlib, shutil, subprocess
from paths import tool

def import_content(jar, cache, runtime):
    done=subprocess.run([tool('java'),'-Djava.awt.headless=true','-cp',str(runtime),'bridge.Main',str(jar),str(cache)],text=True,stdout=subprocess.PIPE,check=True)
    root=pathlib.Path(json.loads(done.stdout.strip().splitlines()[-1])['cache'])
    ffmpeg=os.environ.get('FFMPEG') or shutil.which('ffmpeg')
    amr=list(root.rglob('*.amr'))
    if amr and not ffmpeg:raise RuntimeError('Install FFmpeg or set FFMPEG to its executable to convert JAR audio.')
    for path in amr:
        subprocess.run([ffmpeg,'-v','error','-y','-i',str(path),'-c:a','pcm_s16le',str(path)+'.wav'],check=True)
    midi=list(root.rglob('*.mid'))
    if midi:subprocess.run([tool('java'),'--add-exports','java.desktop/com.sun.media.sound=ALL-UNNAMED','-cp',str(runtime),'bridge.MidiRender',*map(str,midi)],check=True)
    return root
