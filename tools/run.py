#!/usr/bin/env python3
"""Launch the asset-free engine; choose a local JAR in the menu or pass --jar."""
import argparse, os, pathlib, shutil, subprocess, sys
from paths import ROOT
from import_native import prepare

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jar',type=pathlib.Path)
    parser.add_argument('--godot',default=os.environ.get('GODOT_PATH') or shutil.which('godot-4') or shutil.which('godot'))
    parser.add_argument('--compatibility',action='store_true')
    parser.add_argument('--import-only',action='store_true')
    args=parser.parse_args()
    cache=prepare(args.jar) if args.jar else None
    if args.import_only:
        if cache is None:parser.error('--import-only requires --jar')
        print(cache);return 0
    if not args.godot:parser.error('Install Godot 4.7 or pass --godot /path/to/godot.')
    command=[args.godot,'--path',str(ROOT/'game')]
    if args.compatibility:command+=['--rendering-method','gl_compatibility']
    command+=['--','--python',sys.executable]
    if cache:command+=['--cache',str(cache),'--jar',str(args.jar.expanduser().resolve())]
    return subprocess.call(command)
if __name__=='__main__':
    try:sys.exit(main())
    except (OSError,ValueError,RuntimeError,subprocess.CalledProcessError) as error:print(error,file=sys.stderr);sys.exit(1)
