#!/usr/bin/env python3
"""Prepare local game data. Cold imports decode resources and read bounded declarative class-file data.
The running Godot engine reads files only.
"""
import argparse, hashlib, json, pathlib, subprocess, tempfile, shutil, sys, zipfile
from paths import ROOT, cache_home, tool
from build import build
from import_content import import_content
from extract_data import extract
# Developed against the Sony Ericsson release of DEEP 1.0.8. Recorded for reference
# only: any DEEP MIDlet is imported, and conversion decides whether it matches.
VERIFIED='a247f8a872dda268ed8138086bd0de6d038d7faf7ef31469b0efe3eb54209d26'
VERSION='engine-2'

def file_hash(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def importer_hash():
    digest=hashlib.sha256()
    for path in sorted([*(ROOT/'runtime/java').rglob('*.java'),*(ROOT/'tools').glob('*.py')]):
        digest.update(path.relative_to(ROOT).as_posix().encode());digest.update(path.read_bytes())
    return digest.hexdigest()
def portable_importer():
    """The archive salvage and format checks live with the portable converter."""
    browser=str(ROOT/'browser')
    if browser not in sys.path:sys.path.insert(0,browser)
    import import_jar
    return import_jar
def deep_midlet(jar):
    """Accept any DEEP MIDlet archive; reject anything that is not one."""
    try:
        with zipfile.ZipFile(jar) as archive:
            manifest=archive.read('META-INF/MANIFEST.MF').decode('utf-8').replace('\r\n','\n').replace('\n ','')
    except (OSError,KeyError,ValueError,UnicodeDecodeError,zipfile.BadZipFile):return False
    fields=dict(line.split(': ',1) for line in manifest.splitlines() if ': ' in line)
    midlet=[part.strip() for part in fields.get('MIDlet-1','').split(',')]
    return len(midlet)==3 and midlet[2]=='DeepMIDlet'
def model_format_problem(jar):
    with zipfile.ZipFile(jar) as archive:return portable_importer().model_format_problem(archive.namelist())
def readable_copy(jar,directory):
    """The Java converter reads the archive with java.util.zip, which refuses an
    entry whose compressed bytes run a byte short, as one circulating copy of
    the 1.0.8 JAR does. Where the portable importer can salvage every entry
    (declared size and CRC intact), a repacked copy is converted instead; the
    cache stays keyed by the digest of the archive the player actually chose."""
    salvage=portable_importer()
    with zipfile.ZipFile(jar) as archive:
        entries=archive.infolist()
        contents={}
        damaged=False
        for entry in entries:
            if entry.is_dir():continue
            try:contents[entry.filename]=archive.read(entry)
            except (zipfile.BadZipFile,__import__('zlib').error,EOFError):
                contents[entry.filename]=salvage.salvage(archive,entry);damaged=True
    if not damaged:return jar
    copy=pathlib.Path(directory)/'readable.jar'
    with zipfile.ZipFile(copy,'w',zipfile.ZIP_DEFLATED) as out:
        for entry in entries:
            if not entry.is_dir():out.writestr(entry.filename,contents[entry.filename])
    return copy
def valid_cache(directory,digest):
    try:
        stamp=json.loads((directory/'engine-import.json').read_text())
        if stamp.get('version')!=VERSION or stamp.get('jar_sha256')!=digest or stamp.get('converter')!=importer_hash():return False
        if not {'native-data.json','resource_registry.json'}.issubset(stamp['files']):return False
        for name,expected in stamp['files'].items():
            path=pathlib.PurePosixPath(name)
            if path.is_absolute() or '..' in path.parts or '\\' in name:return False
            target=directory/path
            if target.is_symlink() or not target.is_file() or file_hash(target)!=expected:return False
        return True
    except (OSError,ValueError,KeyError,TypeError):return False

def prepare(jar):
    jar=pathlib.Path(jar).expanduser().resolve()
    if jar.stat().st_size>16*1024*1024:raise ValueError('JAR exceeds 16 MiB.')
    if not deep_midlet(jar):raise ValueError('Unsupported JAR: this is not a DEEP MIDlet.')
    problem=model_format_problem(jar)
    if problem:raise ValueError(problem)
    digest=file_hash(jar)
    home=cache_home()/'content';home.mkdir(parents=True,exist_ok=True)
    # Each JAR keys its own cache, so several builds can be imported side by side.
    output=home/digest
    if valid_cache(output,digest):return output
    # An OS-held lock releases on crash. Parallel launches never see partial imports.
    lock=home/'import.lock'
    with lock.open('a+b') as handle:
        if sys.platform=='win32':
            import msvcrt
            handle.seek(0);handle.write(b'0');handle.flush();handle.seek(0);msvcrt.locking(handle.fileno(),msvcrt.LK_LOCK,1)
        else:
            import fcntl
            fcntl.flock(handle,fcntl.LOCK_EX)
        if valid_cache(output,digest):return output
        runtime=build()
        with tempfile.TemporaryDirectory(prefix='import-',dir=home) as temporary:
            source=readable_copy(jar,temporary)
            stage=import_content(source,pathlib.Path(temporary),runtime)
            extract(source,stage,digest)
            files={p.relative_to(stage).as_posix():file_hash(p) for p in sorted(stage.rglob('*')) if p.is_file()}
            (stage/'engine-import.json').write_text(json.dumps({'version':VERSION,'converter':importer_hash(),'jar_sha256':digest,'files':files},indent=2))
            # Publish a complete new cache, retaining old data until conversion succeeds.
            backup=home/(digest+'.previous')
            if backup.exists():shutil.rmtree(backup)
            if output.exists():output.replace(backup)
            try:stage.replace(output)
            except OSError:
                if backup.exists():backup.replace(output)
                raise
            if backup.exists():shutil.rmtree(backup)
    return output
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('jar',type=pathlib.Path);args=parser.parse_args()
    try:print(prepare(args.jar))
    except (OSError,ValueError,RuntimeError,subprocess.CalledProcessError) as error:print(error,file=sys.stderr);sys.exit(1)
