#!/usr/bin/env python3
"""Build the offline adapter from source, into the user's external cache."""
import hashlib, subprocess, tempfile, shutil
from paths import ROOT, cache_home, tool

def build():
    sources=sorted((ROOT/'runtime/java').rglob('*.java'))
    digest=hashlib.sha256()
    for path in sources:
        digest.update(path.relative_to(ROOT).as_posix().encode());digest.update(path.read_bytes())
    output=cache_home()/'adapter'/digest.hexdigest()/'adapter.jar'
    if output.is_file():return output
    output.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as temporary:
        directory=__import__('pathlib').Path(temporary); classes=directory/'classes';classes.mkdir()
        subprocess.run([tool('javac'),'--release','17','-d',str(classes),*map(str,sources)],check=True)
        artifact=directory/'adapter.jar'
        subprocess.run([tool('jar'),'--create','--file',str(artifact),'-C',str(classes),'.'],check=True)
        artifact.replace(output)
    return output
if __name__=='__main__': print(build())
