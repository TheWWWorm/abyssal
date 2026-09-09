#!/usr/bin/env python3
"""Export an engine-only game from manifest-listed source into an external directory."""
import argparse, hashlib, json, os, pathlib, re, shutil, subprocess, tempfile
from paths import ROOT, cache_home
PLATFORMS={'web':('Web','index.html'),'linux':('Linux','abyssal.x86_64'),'windows':('Windows Desktop','abyssal.exe'),'macos':('macOS','abyssal.zip'),'android':('Android','abyssal.apk')}

VIEWPORT_DEFAULT = '<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0">'
VIEWPORT_MOBILE = '<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0, viewport-fit=cover">'
MOBILE_HEAD = """\t\t<meta name="mobile-web-app-capable" content="yes">
\t\t<meta name="apple-mobile-web-app-capable" content="yes">
\t\t<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
\t\t<meta name="apple-mobile-web-app-title" content="Abyssal">
\t\t<meta name="theme-color" content="#03090e">
\t\t<style>
/* Handhelds: fill the viewport and stop the page itself scrolling, bouncing or
   zooming, so drags reach the game as steering rather than moving the page. */
html, body { height: 100%; overscroll-behavior: none; }
body { position: fixed; inset: 0; width: 100%; height: 100%; }
#canvas { width: 100%; height: 100%; touch-action: none; }
\t\t</style>
"""


def stage_mobile_page(html):
    """Make the hosted page behave like an app on a handheld browser."""
    if VIEWPORT_DEFAULT not in html and VIEWPORT_MOBILE not in html:
        raise ValueError('Cannot locate the viewport declaration')
    html = html.replace(VIEWPORT_DEFAULT, VIEWPORT_MOBILE, 1)
    if 'apple-mobile-web-app-capable' not in html:
        html = html.replace('</head>', MOBILE_HEAD + '</head>', 1)
    return html


def stamp_web_build(output):
    """Give each game pack a fresh URL and show which build the page loaded."""
    output=pathlib.Path(output)
    pack=output/'index.pck'
    digest=hashlib.sha256(pack.read_bytes()).hexdigest()
    pack_name=f'game-{digest}.pck'
    # Keep previous versioned packs available for pages opened during an export.
    shutil.copyfile(pack,output/pack_name)
    page=output/'index.html'
    html=page.read_text()
    match=re.search(r'const GODOT_CONFIG = (\{[^\n]+\});',html)
    if match is None:raise ValueError('Cannot locate Godot Web configuration')
    config=json.loads(match.group(1))
    config['mainPack']=pack_name
    config['fileSizes'].pop('index.pck',None)
    config['fileSizes'][pack_name]=pack.stat().st_size
    html=html[:match.start(1)]+json.dumps(config,separators=(',',':'))+html[match.end(1):]
    loader_digest=hashlib.sha256((output/'index.js').read_bytes()).hexdigest()[:12]
    html=html.replace('src="index.js"',f'src="index.js?v={loader_digest}"')
    html=stage_mobile_page(html)
    # Development-build identity stays outside Godot so cached game code cannot
    # report the identity of a newer export. It never accesses player storage.
    # It is recorded in the page head rather than drawn over the running game,
    # where it sat on top of the touch controls.
    html=re.sub(r'<div id="engine-build"[^>]*>.*?</div>\n?', '', html)
    html=re.sub(r'[ \t]*<meta name="engine-build"[^>]*>\n?', '', html)
    html=html.replace('</head>', f'\t\t<meta name="engine-build" content="{digest}">\n</head>', 1)
    temporary=page.with_suffix('.html.tmp');temporary.write_text(html);temporary.replace(page)
    return digest[:12]

def stage_project(stage, platform, version="0.1.0-preview.4", version_code=4):
    names=json.loads((ROOT/'source-manifest.json').read_text())['files']
    for name in names:
        if not name.startswith('game/'):continue
        source=ROOT/name
        if source.is_symlink() or source.suffix not in {'.gd','.gdshader','.gdshaderinc','.tscn','.godot','.uid','.svg'}:raise ValueError('Unexpected runtime source: '+name)
        target=stage/pathlib.Path(name).relative_to('game');target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
    settings=stage/'project.godot'
    text=settings.read_text().replace('renderer/rendering_method="forward_plus"','renderer/rendering_method="gl_compatibility"')
    if platform in {'web','android'}:
        text=text.replace('anti_aliasing/quality/msaa_3d=2','anti_aliasing/quality/msaa_3d=0').replace('atlas_size=8192','atlas_size=2048').replace('directional_shadow/size=4096','directional_shadow/size=1024')
    if platform in {'web','android','macos'}:text=text.replace('[rendering]','[rendering]\n\ntextures/vram_compression/import_etc2_astc=true')
    settings.write_text(text)
    options={'texture_format/s3tc_bptc':'true','texture_format/etc2_astc':'false'}
    if platform=='web':options={'variant/extensions_support':'false','variant/thread_support':'false','vram_texture_compression/for_desktop':'true','vram_texture_compression/for_mobile':'true','html/export_icon':'false','html/canvas_resize_policy':'2','progressive_web_app/enabled':'false'}
    elif platform=='android':options={'architectures/armeabi-v7a':'false','architectures/arm64-v8a':'true','architectures/x86_64':'true','architectures/x86':'false','gradle_build/use_gradle_build':'true','gradle_build/min_sdk':'26','gradle_build/target_sdk':'36','package/unique_name':'"org.abyssal.engine"','package/name':'"Abyssal Engine"','package/signed':'true','version/code':str(version_code),'version/name':json.dumps(version),'screen/immersive_mode':'true','permissions/internet':'false','permissions/read_external_storage':'false','permissions/write_external_storage':'false','permissions/manage_external_storage':'false'}
    elif platform=='macos':options={'application/bundle_identifier':'"org.abyssal.engine"','application/short_version':'"0.1"','application/version':'"0.1"','binary_format/architecture':'"universal"','codesign/codesign':'0','notarization/notarization':'0'}
    else:options['binary_format/architecture']='"x86_64"'
    header=f'''[preset.0]
name="{platform}"
platform="{PLATFORMS[platform][0]}"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
script_export_mode=1

[preset.0.options]
'''
    (stage/'export_presets.cfg').write_text(header+'\n'.join(f'{k}={v}' for k,v in options.items())+'\n')

WEB_HEADERS = """# Served by Cloudflare Pages and other static hosts that read _headers.
# The single-threaded Web export needs no cross-origin isolation.
/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: no-referrer

/*.wasm
  Content-Type: application/wasm

# Game packs carry a content hash in their filename, so they never change in place.
/*.pck
  Cache-Control: public, max-age=31536000, immutable

/importer/vendor/*
  Cache-Control: public, max-age=604800
"""


def write_static_headers(output):
    """Emit a _headers file so static hosts serve WebAssembly and caching correctly."""
    (pathlib.Path(output)/'_headers').write_text(WEB_HEADERS)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--platform',choices=PLATFORMS,required=True);p.add_argument('--output',type=pathlib.Path,required=True,help='An external build directory');p.add_argument('--godot',default=os.environ.get('GODOT_PATH') or shutil.which('godot-4') or shutil.which('godot'));p.add_argument('--release',action='store_true',help='Release template; Android requires configured signing credentials');p.add_argument('--stage-only',action='store_true');p.add_argument('--version',default='0.1.0-preview.4');p.add_argument('--version-code',type=int,default=4);args=p.parse_args()
    if args.version_code<1:p.error("Android version code must be positive")
    output=args.output.expanduser().resolve()
    if output.is_relative_to(ROOT):p.error('Export outside the source directory.')
    if not args.godot and not args.stage_only:p.error('Install Godot 4.7 and matching export templates, or pass --godot.')
    # Same reviewed input set as source packaging. Exported resources never include the local cache.
    from package_source import source_files
    source_files()
    output.mkdir(parents=True,exist_ok=True)
    home=cache_home()/'exports';home.mkdir(parents=True,exist_ok=True)
    if args.stage_only:
        stage=output/'project';stage.mkdir(exist_ok=False);stage_project(stage,args.platform,args.version,args.version_code);print(stage);return
    with tempfile.TemporaryDirectory(prefix=args.platform+'-',dir=home) as temporary:
        stage=pathlib.Path(temporary);stage_project(stage,args.platform,args.version,args.version_code)
        if args.platform=='android':
            from android_runtime import stage as stage_android
            stage_android(stage,args.godot,args.release)
        subprocess.run([args.godot,'--headless','--path',str(stage),'--editor','--import','--quit'],check=True)
        subprocess.run([args.godot,'--headless','--path',str(stage),'--export-release' if args.release else '--export-debug',args.platform,str(output/PLATFORMS[args.platform][1])],check=True)
    if args.platform=='web':
        from browser_runtime import stage as stage_browser_runtime
        stage_browser_runtime(output)
        write_static_headers(output)
        print('Web build:',stamp_web_build(output))
    if args.platform in {"linux","windows","macos"}:
        from desktop_runtime import stage as stage_desktop_runtime, embed_macos
        stage_desktop_runtime(output,args.platform)
        if args.platform=="macos":embed_macos(output)
    # Preserve bundled engine attribution in native/web distributions as well as source.
    subprocess.run([args.godot,'--headless','--script',str(ROOT/'tools/export_notices.gd'),'--',str(output/'GODOT_LICENSES.txt')],check=True)
    shutil.copyfile(ROOT/'THIRD_PARTY_NOTICES.md',output/'THIRD_PARTY_NOTICES.md')
    (output/'licenses').mkdir(exist_ok=True)
    shutil.copyfile(ROOT/'licenses/Apache-2.0.txt',output/'licenses/Apache-2.0.txt')
    print(output/PLATFORMS[args.platform][1])
if __name__=='__main__':main()
