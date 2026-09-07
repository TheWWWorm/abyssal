"""Verify the runtime boundary of reviewed source; this is an evidence gate, not legal clearance."""
import argparse, hashlib, json, pathlib, re
from paths import ROOT
CODE={'.gd','.gdshader','.gdshaderinc','.tscn','.godot','.java','.py','.js'}
FORBIDDEN_RUNTIME=('OriginalClassLoader','SourceAccess','bridge.NativeData','java.lang.reflect.Method','java.lang.reflect.Constructor','java.lang.reflect.Field','Class.forName(','getDeclaredMethod(','URLClassLoader','defineClass(')

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def verify(root=ROOT):
    manifest=json.loads((root/'source-manifest.json').read_text())
    expected={name for name in manifest['files'] if pathlib.Path(name).suffix in CODE}
    for name in sorted(expected):
        path=root/name
        if not path.is_file():raise ValueError('Manifest lists a missing source file: '+name)
        if name.startswith('runtime/java/'):
            content=path.read_text()
            if any(marker in content for marker in FORBIDDEN_RUNTIME):raise ValueError('Original-code runtime dependency reintroduced: '+name)
    result={'reviewed_source_files':len(expected),'legal_clearance':False}
    # The per-file review is kept with the working tree and is not distributed.
    record=root/'provenance/source-provenance.json'
    if not record.is_file():return result|{'local_review':False}
    report=json.loads(record.read_text())
    entries={row['path']:row for row in report['files']}
    if len(entries)!=len(report['files']):raise ValueError('Duplicate provenance record')
    if set(entries)!=expected:raise ValueError('Provenance inventory does not cover the exact source manifest')
    for name in sorted(expected):
        row=entries[name]
        if digest(root/name)!=row['sha256']:raise ValueError('Source changed since provenance review: '+name)
        if not row.get('basis') or not row.get('origin'):raise ValueError('Missing provenance rationale: '+name)
    return result|{'local_review':True,'status':report['legal_status']}

def exact_matches(root,reference,minimum=24):
    """Triage exact token runs only. No similarity percentage or legal threshold.
    Outputs locations, never copies reference source into the distributable tree.
    """
    def tokens(path):
        source=path.read_text(errors='replace');source=re.sub(r'/\*.*?\*/|//[^\n]*|(?m:^\s*#.*$)',' ',source,flags=re.S)
        return re.findall(r'[A-Za-z_$][\w$]*|\d+(?:\.\d+)?|[^\s]',source)
    index={}
    for path in reference.rglob('*'):
        if path.suffix not in {'.java','.fsh','.vsh'}:continue
        words=tokens(path)
        for offset in range(max(0,len(words)-minimum+1)):
            key=hashlib.sha256('\0'.join(words[offset:offset+minimum]).encode()).digest()
            index.setdefault(key,set()).add(path.relative_to(reference).as_posix())
    findings=[]
    for path in root.rglob('*'):
        if path.suffix not in {'.java','.gd','.gdshader'}:continue
        words=tokens(path);matches={}
        for offset in range(max(0,len(words)-minimum+1)):
            key=hashlib.sha256('\0'.join(words[offset:offset+minimum]).encode()).digest()
            for origin in index.get(key,()):matches[origin]=matches.get(origin,0)+1
        if matches:findings.append({'path':path.relative_to(root).as_posix(),'matching_reference_windows':matches})
    return findings
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--reference',type=pathlib.Path);args=p.parse_args()
    print(json.dumps(exact_matches(ROOT,args.reference) if args.reference else verify(),indent=2))
