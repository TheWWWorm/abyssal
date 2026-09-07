#!/usr/bin/env python3
"""Package the reviewed source manifest; no recursive asset inclusion."""
import argparse, hashlib, json, pathlib, zipfile
from paths import ROOT
from audit_provenance import verify as verify_provenance
MANIFEST=ROOT/'source-manifest.json'
ALLOWED={'.gd','.gdshader','.gdshaderinc','.tscn','.godot','.java','.py','.md','.txt','.json','.uid','.js','.toml'}
IGNORED={'.godot','__pycache__','.git','public'}

def source_files():
    names=json.loads(MANIFEST.read_text())['files']
    if len(names)!=len(set(names)):raise ValueError('Duplicate source manifest entry')
    files=[]
    for name in names:
        rel=pathlib.PurePosixPath(name)
        if rel.is_absolute() or '..' in rel.parts or '\\' in name:raise ValueError(f'Unsafe source path: {name}')
        path=ROOT/name
        if not path.is_file() or any(p.is_symlink() for p in [path,*path.parents]):raise ValueError(f'Missing source or symbolic link: {name}')
        if path.suffix not in ALLOWED and name!='.gitignore':raise ValueError(f'Unreviewed file type: {name}')
        if path.read_bytes()[:4] in [b'PK\x03\x04',b'\xca\xfe\xba\xbe',b'\x89PNG',b'glTF',b'RIFF',b'OggS']:raise ValueError(f'Binary payload disguised as source: {name}')
        files.append(path)
    expected=set(names)|{'source-manifest.json','SHA256SUMS.json','provenance/source-provenance.json'}
    actual={p.relative_to(ROOT).as_posix() for p in ROOT.rglob('*') if p.is_file() and not any(x in IGNORED for x in p.relative_to(ROOT).parts) and p.suffix!='.uid'}
    extra=actual-expected
    if extra:raise ValueError('Unreviewed files in engine tree: '+', '.join(sorted(extra)))
    # Generated archive metadata is checked, never treated as distributable input.
    checksums=ROOT/'SHA256SUMS.json'
    if checksums.exists():
        if checksums.is_symlink():raise ValueError('Symbolic link checksum manifest')
        recorded=json.loads(checksums.read_text())
        current={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in [*files,MANIFEST]}
        if recorded!=current:raise ValueError('Archive source checksums differ; remove SHA256SUMS.json after intentional edits.')
    verify_provenance(ROOT)
    return [*files,MANIFEST]

def package(output):
    output=pathlib.Path(output).expanduser().resolve()
    if output.is_relative_to(ROOT):raise ValueError('Write archives outside the source tree.')
    files=source_files();output.parent.mkdir(parents=True,exist_ok=True)
    hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    with zipfile.ZipFile(output,'w',compression=zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            info=zipfile.ZipInfo('abyssal-engine/'+path.relative_to(ROOT).as_posix(),date_time=(2026,9,6,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16
            archive.writestr(info,path.read_bytes())
        archive.writestr('abyssal-engine/SHA256SUMS.json',json.dumps(hashes,indent=2,sort_keys=True))
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:raise ValueError('Archive verification failed')
    return {'archive':str(output),'files':len(files),'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'license_status':'pending legal/ownership release review; development source only'}
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',required=True,type=pathlib.Path);args=parser.parse_args()
    print(json.dumps(package(args.output),indent=2))
