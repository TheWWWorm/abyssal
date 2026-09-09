#!/usr/bin/env python3
"""Build downloadable engine-only previews with offline JAR import."""
import argparse,hashlib,json,pathlib,re,shutil,subprocess,sys,tarfile,tempfile,zipfile
from paths import ROOT

VALIDATION_PENDING = "# Platform support\n\nThese packages were exported without a device validation record. Export success alone does not establish native execution, fresh JAR import or gameplay compatibility. Windows/macOS packages are unsigned. See README.md for platform requirements.\n"


def add_documents(folder):
    (folder/"VALIDATION.md").write_text(VALIDATION_PENDING)
    for name in ['README.md','LICENSE.md','THIRD_PARTY_NOTICES.md']:
        shutil.copyfile(ROOT/name,folder/name)
    (folder/"provenance").mkdir(exist_ok=True)
    for name in ["decoder-provenance.json"]:
        shutil.copyfile(ROOT/"provenance"/name,folder/"provenance"/name)


def archive_build(folder,target,platform):
    """No private input/cache belongs in a release; preserve executable modes."""
    files=sorted(p for p in folder.rglob('*') if p.is_file() or p.is_symlink())
    if any(p.is_symlink() or p.suffix.lower() in {'.jar','.abyss','.class'} for p in files):
        raise ValueError('Private content or symlink in release staging')
    if platform=='linux':
        with tarfile.open(target,'w:gz') as archive:
            for p in files:archive.add(p,arcname='AbyssalEngine/'+p.relative_to(folder).as_posix(),recursive=False)
    else:
        with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as archive:
            for p in files:
                if platform=='macos' and p.name=='abyssal.zip':
                    with zipfile.ZipFile(p) as app:
                        for info in app.infolist():archive.writestr(info,app.read(info.filename))
                else:archive.write(p,p.relative_to(folder).as_posix())


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=pathlib.Path,required=True)
    parser.add_argument('--version',default='0.1.0-preview.4')
    parser.add_argument('--platform',action='append',choices=['linux','windows','macos','web','android'])
    parser.add_argument('--godot',default=shutil.which('godot-4') or shutil.which('godot'))
    parser.add_argument('--version-code',type=int,default=4,help='Monotonically increasing Android version code')
    parser.add_argument('--validation',type=pathlib.Path,help='Player-facing platform support notes included with the release')
    args=parser.parse_args()
    if not re.fullmatch(r'[0-9][A-Za-z0-9.-]{0,60}',args.version):parser.error('Invalid version identifier')
    if args.version_code<1:parser.error("Android version code must be positive")
    output=args.output.expanduser().resolve()
    if output.is_relative_to(ROOT):parser.error('Keep releases outside the engine source tree')
    output.mkdir(parents=True,exist_ok=True)
    platforms=args.platform or ['linux','windows','macos','web','android']
    records=[]
    for platform in platforms:
        with tempfile.TemporaryDirectory(prefix='release-'+platform+'-',dir=output) as temp:
            folder=pathlib.Path(temp)/'build'
            subprocess.run([sys.executable,str(ROOT/'tools/export_game.py'),'--platform',platform,'--output',str(folder),'--release','--godot',args.godot,'--version',args.version,'--version-code',str(args.version_code)],check=True)
            add_documents(folder)
            if args.validation:shutil.copyfile(args.validation,folder/"VALIDATION.md")
            name=f'abyssal-engine-{args.version}-{platform}'+('.tar.gz' if platform=='linux' else '.apk' if platform=='android' else '.zip')
            target=output/name
            if target.exists():raise FileExistsError('Release archive already exists: '+str(target))
            if platform=="android":shutil.copyfile(folder/"abyssal.apk",target)
            else:archive_build(folder,target,platform)
            records.append({'platform':platform,'file':name,'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'template':'release','signing':'unsigned' if platform in ['windows','macos'] else 'release key' if platform=='android' else 'not applicable','direct_jar_import':True})
    metadata={'version':args.version,'channel':'preview','source_manifest_sha256':hashlib.sha256((ROOT/'source-manifest.json').read_bytes()).hexdigest(),'artifacts':records,'testing':'See VALIDATION.md for actual execution results; export success is not device validation.'}
    (output/'VALIDATION.md').write_text(args.validation.read_text() if args.validation else VALIDATION_PENDING)
    (output/'release.json').write_text(json.dumps(metadata,indent=2)+'\n')
    (output/'SHA256SUMS').write_text(''.join(f"{r['sha256']}  {r['file']}\n" for r in records))
    print(json.dumps(metadata,indent=2))
if __name__=='__main__':main()
