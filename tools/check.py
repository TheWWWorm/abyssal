#!/usr/bin/env python3
"""Run engine regression checks without bundling proprietary test fixtures."""
import argparse, pathlib, subprocess, sys, shutil, tempfile
from paths import ROOT

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--cache',type=pathlib.Path,required=True);p.add_argument('--godot',default=shutil.which('godot-4') or shutil.which('godot'));p.add_argument('--gpu',action='store_true');p.add_argument('--compatibility',action='store_true');args=p.parse_args()
    if not args.godot:p.error('Pass --godot or install Godot 4.7')
    cache=args.cache.resolve()
    from pack_content import pack
    temporary=tempfile.TemporaryDirectory(prefix="abyssal-pack-check-")
    portable=pathlib.Path(temporary.name)/"private.abyss"
    pack(cache,portable)
    cases={
        "platform_input_check.gd":cache,
        "gamepad_ui_check.gd":cache,
        "readability_check.gd":cache,
        "content_pack_check.gd":portable,
        'native_session_check.gd':cache/'native-data.json',
        'modern_gameplay_check.gd':cache/'native-data.json',
        'provenance_rules_check.gd':cache/'native-data.json',
        'native_travel_check.gd':cache/'native-data.json',
        'native_open_world_mission_check.gd':cache/'native-data.json',
        'native_stream_check.gd':cache,
        'native_terrain_check.gd':cache,
        'engine_ui_check.gd':cache,
        'engine_stream_check.gd':cache,
    }
    failures=[]
    for name,argument in cases.items():
        command=[args.godot,'--path',str(ROOT/'game')]
        if not args.gpu:command+=['--headless']
        if args.compatibility:command+=['--rendering-method','gl_compatibility']
        command+=['--script',str(ROOT/'tests'/name),'--',str(argument)]
        try:
            result=subprocess.run(command,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
            bad=result.returncode!=0 or 'SCRIPT ERROR:' in result.stdout or 'ERROR:' in result.stdout
            print(('FAIL ' if bad else 'PASS ')+name,flush=True)
            print(result.stdout.strip(),flush=True)
            if bad:failures.append(name)
        except subprocess.TimeoutExpired:
            failures.append(name);print('FAIL '+name+' (timeout)',flush=True)
    print(f'{len(cases)-len(failures)}/{len(cases)} checks passed')
    temporary.cleanup()
    return bool(failures)
if __name__=='__main__':sys.exit(main())
