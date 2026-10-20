"""Shared application artwork inventory and browser branding export."""
import hashlib
import json
from pathlib import Path
import re
import shutil
from paths import ROOT

# Exact paths only; imported game images are never distributable inputs.
ARTWORK = {
    'game/ui/abyssal-icon.png', 'game/ui/abyssal-splash.png',
    'game/ui/abyssal-splash-fsr.png', 'game/ui/vendors/amd-fsr-upscaling-white.png',
    'game/ui/vendors/amd-fsr-frame-generation-white.png',
    'game/ui/abyssal-icon.ico', 'game/ui/abyssal-icon.icns',
    'browser/favicon.png', 'browser/apple-touch-icon.png',
    'browser/icon-192.png', 'browser/icon-512.png',
}


def web_assets(output, html):
    """Use the same approved art for loading, favicons and home-screen icons."""
    output = Path(output)
    source = ROOT/'game/ui/abyssal-icon.png'
    version = hashlib.sha256(source.read_bytes()).hexdigest()[:12]
    for name, asset in {
        'index.png': 'game/ui/abyssal-splash.png',
        'index.icon.png': 'browser/favicon.png',
        'favicon.ico': 'game/ui/abyssal-icon.ico',
        'index.apple-touch-icon.png': 'browser/apple-touch-icon.png',
        'icon-192.png': 'browser/icon-192.png', 'icon-512.png': 'browser/icon-512.png',
    }.items():
        shutil.copyfile(ROOT/asset, output/name)
    manifest = {
        'name': 'Abyssal', 'short_name': 'Abyssal', 'start_url': './', 'scope': './',
        'display': 'standalone', 'background_color': '#03090e', 'theme_color': '#03090e',
        'icons': [{'src': f'icon-{size}.png?v={version}', 'sizes': f'{size}x{size}', 'type': 'image/png', 'purpose': 'any'} for size in [192, 512]],
    }
    (output/'manifest.webmanifest').write_text(json.dumps(manifest, indent=2)+'\n')
    html = re.sub(r'<link\b[^>]*\brel=["\'](?:icon|shortcut icon|apple-touch-icon|manifest)["\'][^>]*>\s*', '', html, flags=re.I)
    links = (
        f'\t\t<link rel="icon" type="image/x-icon" href="favicon.ico?v={version}">\n'
        f'\t\t<link rel="apple-touch-icon" sizes="180x180" href="index.apple-touch-icon.png?v={version}">\n'
        f'\t\t<link rel="manifest" href="manifest.webmanifest?v={version}">\n'
    )
    return html.replace('</head>', links+'</head>', 1)
