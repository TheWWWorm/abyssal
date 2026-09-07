"""Stage offline JAR conversion and pinned Node binaries into desktop exports."""
import hashlib
import json
import pathlib
import shutil
import struct
import tarfile
import urllib.request
import zipfile
from paths import ROOT, cache_home
from browser_runtime import stage as stage_importer


def fetch(record):
    cache=cache_home()/'desktop-runtime';cache.mkdir(parents=True,exist_ok=True)
    target=cache/record['sha256']
    if target.is_file() and hashlib.sha256(target.read_bytes()).hexdigest()==record['sha256']:return target
    print('Fetching desktop runtime:',record['platform'],flush=True)
    with urllib.request.urlopen(record['url'],timeout=60) as response:
        payload=response.read(256*1024*1024+1)
    if len(payload)>256*1024*1024 or hashlib.sha256(payload).hexdigest()!=record['sha256']:
        raise ValueError('Node runtime checksum mismatch: '+record['platform'])
    pending=target.with_suffix('.partial');pending.write_bytes(payload);pending.replace(target)
    return target


def stage(output,platform):
    output=pathlib.Path(output)
    importer=stage_importer(output,web=False)
    shutil.copyfile(ROOT/'desktop/import.js',importer/'import.js')
    lock=json.loads((ROOT/'desktop/dependencies.json').read_text())
    for record in lock['files']:
        if record['platform']!=platform and not (platform=='macos' and record['platform'].startswith('macos-')):continue
        archive=fetch(record)
        if record['url'].endswith('.zip'):
            with zipfile.ZipFile(archive) as bundle:
                binary=bundle.read(record['member']);license_text=bundle.read(record['license_member'])
        else:
            with tarfile.open(archive,'r:*') as bundle:
                binary=bundle.extractfile(record['member']).read();license_text=bundle.extractfile(record['license_member']).read()
        executable=importer/'bin'/record['platform']/('node.exe' if platform=='windows' else 'node')
        executable.parent.mkdir(parents=True,exist_ok=True);executable.write_bytes(binary);executable.chmod(0o755)
        (importer/'licenses/Node.txt').write_bytes(license_text)
    shutil.copyfile(ROOT/'desktop/dependencies.json',importer/'desktop-dependencies.json')
    return importer


FAT_MAGIC,FAT_MAGIC_64,CPU_TYPE_ARM64=0xCAFEBABE,0xCAFEBABF,0x0100000C


def thin_arm64(data):
    """Return the arm64 slice of a Mach-O universal binary, as `lipo -thin arm64` does.

    Godot's official macOS export template contains a universal binary, so an
    Apple Silicon-only package keeps that slice and drops the Intel one. The
    slice is itself a complete Mach-O image. Format: mach-o/fat.h, big-endian.
    """
    magic,=struct.unpack_from('>I',data,0)
    if magic not in {FAT_MAGIC,FAT_MAGIC_64}:raise ValueError('Not a Mach-O universal binary')
    wide=magic==FAT_MAGIC_64
    count,=struct.unpack_from('>I',data,4)
    if not 1<=count<=32:raise ValueError('Unreasonable architecture count')
    cursor,width=8,32 if wide else 20
    for _ in range(count):
        cpu,_subtype,offset,length=struct.unpack_from('>iiQQ' if wide else '>iiII',data,cursor)
        cursor+=width
        if cpu&0xFFFFFFFF!=CPU_TYPE_ARM64:continue
        if offset+length>len(data):raise ValueError('Architecture slice runs past end of binary')
        return data[offset:offset+length]
    raise ValueError('No arm64 slice in macOS template binary')


def embed_macos(output):
    """Add the Apple Silicon runtime inside .app Resources, keeping only the arm64 engine slice."""
    output=pathlib.Path(output);archive=output/'abyssal.zip'
    with zipfile.ZipFile(archive) as bundle:
        roots={name.split('/')[0] for name in bundle.namelist() if '.app/Contents/' in name}
        if len(roots)!=1:raise ValueError('Expected one macOS app bundle')
        root=roots.pop()
        entries=[(info,bundle.read(info.filename)) for info in bundle.infolist()]
    executables=root+'/Contents/MacOS/';prefix=root+'/Contents/Resources/';thinned=0
    pending=archive.with_name('abyssal.arm64.zip')
    with zipfile.ZipFile(pending,'w',zipfile.ZIP_DEFLATED) as bundle:
        for info,payload in entries:
            if info.filename.startswith(executables) and not info.is_dir():
                payload=thin_arm64(payload);thinned+=1
            bundle.writestr(info,payload)
        for source in sorted((output/'importer').rglob('*')):
            if source.is_file():bundle.write(source,prefix+source.relative_to(output).as_posix())
    if thinned!=1:raise ValueError('Expected exactly one macOS executable to thin')
    pending.replace(archive)
    shutil.rmtree(output/'importer')
