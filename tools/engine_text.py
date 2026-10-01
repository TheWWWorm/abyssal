#!/usr/bin/env python3
"""Engine text catalogs: list the text the engine marks for translation and
check every catalog against it.

The engine marks its own player-facing text with tr("...") or
translate("..."); the English text is the key. Each catalog in
game/native/locale/<code>.gd maps those keys to one language.

  engine_text.py keys             print the marked text as a JSON list
  engine_text.py check            fail on missing, stale or broken entries
  engine_text.py missing <code>   print the keys a catalog lacks as JSON
  engine_text.py write <code> <json>
                                  merge {key: translation} into a catalog
  engine_text.py fonts <NotoSansCJK-Regular.ttc> <harfbuzz-subset.wasm>
                                  write the CJK glyph subsets the catalogs need

The CJK subsets come from Noto Sans CJK (SIL Open Font License 1.1) through
tools/subset_font.js, which needs Node and the harfbuzzjs package's
harfbuzz-subset.wasm. Run it after changing the zh, ja or ko catalog.
"""
import json, pathlib, re, struct, subprocess, sys, tempfile
from paths import ROOT

CODE = ROOT/'game/native'
LOCALE = CODE/'locale'
LANGUAGES = CODE/'presentation/engine_language.gd'
CALL = re.compile(r'(?<![\w.])(?:tr|translate|EngineLanguage\.translate|Language\.translate)\(\s*("(?:[^"\\\n]|\\.)*"|\'(?:[^\'\\\n]|\\.)*\')\s*[,)]')
PLACEHOLDER = re.compile(r'%(?:%|[-+ 0#]*\d*(?:\.\d+)?[sdcfxXov])')

def unquote(literal):
    body = literal[1:-1]
    return re.sub(r'\\(u[0-9a-fA-F]{4}|.)', lambda m: chr(int(m.group(1)[1:], 16)) if m.group(1)[0]=='u' and len(m.group(1))==5 else {'n':'\n','t':'\t','r':'\r'}.get(m.group(1), m.group(1)), body)

def keys():
    found = {}
    for path in sorted(CODE.rglob('*.gd')):
        if LOCALE in path.parents: continue
        for match in CALL.finditer(path.read_text(encoding='utf-8')):
            found.setdefault(unquote(match.group(1)), str(path.relative_to(ROOT)))
    return found

def languages():
    text = LANGUAGES.read_text(encoding='utf-8')
    return re.findall(r'\["(\w+)","[^"]+","res://native/locale/\1\.gd"\]', text)

def read(code):
    path = LOCALE/f'{code}.gd'
    if not path.exists(): return {}
    body = path.read_text(encoding='utf-8')
    start = body.index('const TEXT := {')+len('const TEXT := ')
    return json.loads(body[start:])

def write(code, entries):
    name = next((n for c, n in re.findall(r'\["(\w+)","([^"]+)"', LANGUAGES.read_text(encoding='utf-8')) if c==code), code)
    lines = [f'\t{json.dumps(k, ensure_ascii=False)}: {json.dumps(v, ensure_ascii=False)},' for k, v in sorted(entries.items())]
    if lines: lines[-1] = lines[-1][:-1]
    LOCALE.mkdir(exist_ok=True)
    (LOCALE/f'{code}.gd').write_text('extends RefCounted\n'
        f'## Engine text in {name}. Keys are the English text the engine marks with\n'
        '## tr(). Write it with tools/engine_text.py; keep each placeholder in order.\n'
        'const TEXT := {\n'+'\n'.join(lines)+'\n}\n', encoding='utf-8')

# Language, face in NotoSansCJK-Regular.ttc, bundled file.
FONTS = {'zh': (2, 'noto_sans_sc.otf'), 'ja': (0, 'noto_sans_jp.otf'), 'ko': (1, 'noto_sans_kr.otf')}
NATIVE_NAMES = {'zh': '简体中文', 'ja': '日本語', 'ko': '한국어'}

def needs_font(character):
    """Hangul, kana, CJK ideographs and their punctuation: none of these are in
    the interface font."""
    c = ord(character)
    return 0x1100<=c<=0x11ff or 0x2e80<=c<=0x9fff or 0xac00<=c<=0xd7af or 0xf900<=c<=0xfaff or 0xff00<=c<=0xffef

def font_characters(code):
    text = NATIVE_NAMES[code]+''.join(read(code).values())
    return sorted({c for c in text if ord(c)>=0x2000})

def cmap(path):
    """The characters an OpenType font maps, from its format 4 or 12 cmap."""
    data = path.read_bytes()
    tables = {data[12+16*i:16+16*i]: struct.unpack('>II', data[20+16*i:28+16*i]) for i in range(struct.unpack('>H', data[4:6])[0])}
    base = tables[b'cmap'][0]; found = set()
    for i in range(struct.unpack('>H', data[base+2:base+4])[0]):
        offset = base+struct.unpack('>I', data[base+8+8*i:base+12+8*i])[0]
        kind = struct.unpack('>H', data[offset:offset+2])[0]
        if kind==12:
            for g in range(struct.unpack('>I', data[offset+12:offset+16])[0]):
                start, end, _ = struct.unpack('>III', data[offset+16+12*g:offset+28+12*g]); found.update(range(start, end+1))
        elif kind==4:
            segments = struct.unpack('>H', data[offset+6:offset+8])[0]//2
            ends = struct.unpack(f'>{segments}H', data[offset+14:offset+14+2*segments])
            starts = struct.unpack(f'>{segments}H', data[offset+16+2*segments:offset+16+4*segments])
            for start, end in zip(starts, ends):
                if start!=0xffff: found.update(range(start, end+1))
    return found

def fonts(source, wasm):
    for code, (face, name) in FONTS.items():
        with tempfile.NamedTemporaryFile('w', encoding='utf-8', suffix='.txt') as characters:
            characters.write(''.join(font_characters(code))); characters.flush()
            subprocess.run(['node', str(ROOT/'tools/subset_font.js'), wasm, source, str(face), characters.name, str(LOCALE/name)], check=True)
        print(name, (LOCALE/name).stat().st_size, 'bytes')

def problems():
    wanted = keys(); found = []
    for code, (_, name) in FONTS.items():
        if code not in languages(): continue
        covered = cmap(LOCALE/name) if (LOCALE/name).exists() else set()
        missing = sorted({c for c in NATIVE_NAMES[code]+''.join(read(code).values()) if needs_font(c) and ord(c) not in covered})
        if missing: found.append(f'{code}: {name} lacks {len(missing)} characters, run fonts: {"".join(missing[:20])}')
    for code in languages():
        catalog = read(code)
        for key in wanted:
            if key not in catalog: found.append(f'{code}: missing {key!r}')
            elif PLACEHOLDER.findall(key)!=PLACEHOLDER.findall(catalog[key]):
                found.append(f'{code}: placeholders differ in {key!r}')
            elif not catalog[key].strip(): found.append(f'{code}: empty {key!r}')
        for key in catalog:
            if key not in wanted: found.append(f'{code}: stale {key!r}')
    return found

def main(argv):
    if argv[:1]==['keys']: print(json.dumps(sorted(keys()), ensure_ascii=False, indent=1))
    elif argv[:1]==['missing']:
        catalog = read(argv[1]); print(json.dumps([k for k in sorted(keys()) if k not in catalog], ensure_ascii=False, indent=1))
    elif argv[:1]==['write']:
        catalog = read(argv[1]); catalog.update(json.loads(pathlib.Path(argv[2]).read_text(encoding='utf-8')))
        wanted = keys(); write(argv[1], {k: v for k, v in catalog.items() if k in wanted})
    elif argv[:1]==['fonts']: fonts(argv[1], argv[2])
    elif argv[:1]==['check']:
        found = problems()
        for line in found[:60]: print(line)
        print(f'{len(keys())} engine texts; {len(languages())} catalogs; {len(found)} problems')
        return 1 if found else 0
    else: print(__doc__); return 2
    return 0

if __name__=='__main__': sys.exit(main(sys.argv[1:]))
