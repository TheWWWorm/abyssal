#!/usr/bin/env python3
"""Fetch and verify the pinned NVIDIA Streamline SDK for the Windows FSR and DLSS build.

Writes the SDK headers into a Godot source tree patched with
engine/godot-4.7/nvidia-dlss.patch, and NVIDIA's production runtime and
license files into an external directory for export_game.py --streamline.
Nothing from the SDK is kept in this repository."""
import argparse, hashlib, pathlib, shutil, urllib.request, zipfile

VERSION='2.14.16'
SHA256='32041e51db0cab709a271b72a352281b690c2abbd669a827809401a5dd23956b'
URL=f'https://github.com/NVIDIA-RTX/Streamline/releases/download/v{VERSION}/streamline-sdk-v{VERSION}.zip'
# Production builds only; the SDK's development and debug DLLs are never shipped.
DLLS=('sl.interposer.dll','sl.common.dll','sl.dlss.dll','sl.dlss_g.dll','sl.reflex.dll','sl.pcl.dll','nvngx_dlss.dll','nvngx_dlssg.dll')
NOTICES=('license.txt','3rd-party-licenses.md','external/ngx-sdk/license.txt','bin/x64/nvngx_dlss.license.txt','bin/x64/reflex.license.txt')

def prepare(archive,output,engine=None):
    if not archive.exists():
        archive.parent.mkdir(parents=True,exist_ok=True)
        partial=archive.with_suffix('.partial')
        with urllib.request.urlopen(URL) as source,partial.open('wb') as target:shutil.copyfileobj(source,target)
        partial.replace(archive)
    with archive.open('rb') as data:
        if hashlib.file_digest(data,'sha256').hexdigest()!=SHA256:raise ValueError('Streamline SDK checksum mismatch')
    with zipfile.ZipFile(archive) as sdk:
        names=[n for n in sdk.namelist() if n.startswith('include/') and not n.endswith('/')]
        names+=['bin/x64/'+n for n in DLLS]+list(NOTICES)
        for name in names:
            if '..' in pathlib.PurePosixPath(name).parts:raise ValueError('Unsafe SDK member: '+name)
            path=output/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(sdk.read(name))
    if engine:shutil.copytree(output/'include',engine/'thirdparty/streamline/include',dirs_exist_ok=True)
    print(f'Verified Streamline {VERSION}: {output}')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archive',type=pathlib.Path,required=True,help='Downloaded here when missing')
    p.add_argument('--output',type=pathlib.Path,required=True,help='An external directory')
    p.add_argument('--engine',type=pathlib.Path,help='Patched Godot 4.7 source tree')
    args=p.parse_args()
    prepare(args.archive.resolve(),args.output.resolve(),args.engine.resolve() if args.engine else None)
