#!/usr/bin/env python3
"""Build downloadable engine-only previews with offline desktop JAR import."""
import argparse,hashlib,json,pathlib,re,shutil,subprocess,sys,tarfile,tempfile,zipfile
from paths import ROOT

VALIDATION_PENDING = "# Validation pending\n\nThese archives were exported and packaged automatically. Native execution, fresh JAR import and gameplay checks have not been recorded for this build. Export success is not device validation. Replace this note with actual target-specific results before publication. Windows/macOS packages are unsigned.\n"


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
    parser.add_argument('--version',default='0.1.0-preview.1')
    parser.add_argument('--platform',action='append',choices=['linux','windows','macos','web'])
    parser.add_argument('--godot',default=shutil.which('godot-4') or shutil.which('godot'))
    args=parser.parse_args()
    if not re.fullmatch(r'[0-9][A-Za-z0-9.-]{0,60}',args.version):parser.error('Invalid version identifier')
    output=args.output.expanduser().resolve()
    if output.is_relative_to(ROOT):parser.error('Keep releases outside the engine source tree')
    output.mkdir(parents=True,exist_ok=True)
    platforms=args.platform or ['linux','windows','macos','web']
    records=[]
    for platform in platforms:
        with tempfile.TemporaryDirectory(prefix='release-'+platform+'-',dir=output) as temp:
            folder=pathlib.Path(temp)/'build'
            subprocess.run([sys.executable,str(ROOT/'tools/export_game.py'),'--platform',platform,'--output',str(folder),'--release','--godot',args.godot],check=True)
            add_documents(folder)
            name=f'abyssal-engine-{args.version}-{platform}'+('.tar.gz' if platform=='linux' else '.zip')
            target=output/name
            if target.exists():raise FileExistsError('Release archive already exists: '+str(target))
            archive_build(folder,target,platform)
            records.append({'platform':platform,'file':name,'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'template':'release','signing':'unsigned' if platform in ['windows','macos'] else 'not applicable','direct_jar_import':True})
    metadata={'version':args.version,'channel':'preview','source_manifest_sha256':hashlib.sha256((ROOT/'source-manifest.json').read_bytes()).hexdigest(),'artifacts':records,'testing':'See VALIDATION.md for actual execution results; export success is not device validation.'}
    (output/'VALIDATION.md').write_text(VALIDATION_PENDING)
    (output/'release.json').write_text(json.dumps(metadata,indent=2)+'\n')
    (output/'SHA256SUMS').write_text(''.join(f"{r['sha256']}  {r['file']}\n" for r in records))
    print(json.dumps(metadata,indent=2))
if __name__=='__main__':main()
