"""Writable per-user locations, kept outside the distributable source tree."""
import os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def cache_home():
    if os.environ.get('ABYSSAL_CACHE_HOME'):
        return Path(os.environ['ABYSSAL_CACHE_HOME']).expanduser().resolve()
    if os.name=='nt':
        base=Path(os.environ.get('LOCALAPPDATA',Path.home()/'AppData/Local'))
    elif __import__('sys').platform=='darwin':
        base=Path.home()/'Library/Caches'
    else:
        base=Path(os.environ.get('XDG_CACHE_HOME',Path.home()/'.cache'))
    return base/'abyssal-engine'
def tool(name):
    import shutil
    override=os.environ.get(name.upper()+'_PATH')
    found=override or shutil.which(name)
    if not found: raise RuntimeError(f'{name} is required. Install it or set {name.upper()}_PATH.')
    return found
