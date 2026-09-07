#!/usr/bin/env python3
"""Prepare a private portable .abyss content pack for desktop, Android or browser."""
import argparse, hashlib, json, pathlib, re, zipfile
from import_native import prepare
from paths import ROOT
MAX_FILE=32*1024*1024
MAX_TOTAL=128*1024*1024

def pack(cache, output):
    cache=pathlib.Path(cache).resolve();output=pathlib.Path(output).expanduser().resolve()
    if output.is_relative_to(ROOT) or output.is_relative_to(cache):raise ValueError('Keep private content packs outside the source and content directories.')
    native=json.loads((cache/'native-data.json').read_text())
    # The pack carries the digest of the JAR it was converted from, whichever build that was.
    profile=native.get('jar_sha256','')
    if not re.fullmatch(r'[0-9a-f]{64}',profile) or native.get('importer')!='native-6':raise ValueError('Reimport your JAR with the current importer.')
    # Explicit data roots; never include classes, converter outputs or executables.
    paths=[cache/'native-data.json',cache/'resource_registry.json',cache/'bindings.json']
    paths+=sorted((cache/'data').rglob('*'))
    records={};total=0
    for path in paths:
        if path.is_symlink():raise ValueError('Symlinks are not portable content.')
        if path.is_dir():continue
        name=path.relative_to(cache).as_posix()
        if path.suffix.lower() in {'.class','.jar','.gd','.exe','.dll','.so','.py','.js'}:raise ValueError('Executable content is forbidden: '+name)
        size=path.stat().st_size;total+=size
        if size>MAX_FILE or total>MAX_TOTAL:raise ValueError('Content exceeds portable limits.')
        records[name]={'size':size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    if len(records)>4095:raise ValueError('Too many content files.')
    manifest={'format':'abyssal-content-1','profile':profile,'files':records}
    output.parent.mkdir(parents=True,exist_ok=True)
    temporary=output.with_suffix(output.suffix+'.partial')
    try:
        with zipfile.ZipFile(temporary,'w',zipfile.ZIP_DEFLATED) as z:
            z.writestr('pack.json',json.dumps(manifest,sort_keys=True,separators=(',',':')))
            for name in records:z.write(cache/name,name)
        temporary.replace(output)
    finally:temporary.unlink(missing_ok=True)
    return {'pack':str(output),'files':len(records),'bytes':output.stat().st_size,'private_content':True}
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);g=p.add_mutually_exclusive_group(required=True);g.add_argument('--jar',type=pathlib.Path);g.add_argument('--cache',type=pathlib.Path);p.add_argument('--output',required=True,type=pathlib.Path);args=p.parse_args()
    print(json.dumps(pack(prepare(args.jar) if args.jar else args.cache,args.output),indent=2))
