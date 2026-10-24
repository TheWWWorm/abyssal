#!/usr/bin/env python3
"""Fetch and verify the pinned AMD FidelityFX SDK for the Windows FSR build.

Writes the SDK headers into a Godot source tree patched with
engine/godot-4.7/amd-fsr.patch (or amd-fsr-after-nvidia-dlss.patch), and
AMD's signed runtime, the DirectX Agility runtime FSR 4 needs and their
license files into an external directory for export_game.py --fsr-sdk.
Nothing from either SDK is kept in this repository."""
import argparse, hashlib, pathlib, shutil, urllib.request, zipfile

VERSION='2.3.0'
BASE=f'https://raw.githubusercontent.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/v{VERSION}/'
FILES={
    '3rdpartynotice.md':'94401a90486d1b53b528bb7f845a7b8daf7227b60eb7c0fc3b8c5571ba202a27',
    'Kits/FidelityFX/api/include/dx12/ffx_api_dx12.h':'c9afbc3c4c673723e9e5369a666f0ff54560543b5a93537f8ff453bf1c3bf530',
    'Kits/FidelityFX/api/include/ffx_api.h':'e1a9d1b559eaf75f4cb401f1c43a66e2f3dc9621abfeb58b9c6fac56443177fd',
    'Kits/FidelityFX/api/include/ffx_api_types.h':'cc0adc0ffc804dd7cd03c39c15581b575e416383177ffe95060201d52cc0fc49',
    'Kits/FidelityFX/docs/license.md':'6757f2fec461238da6f84f83536ec195e8c036b1773a06f6f34301b9ed8c0963',
    'Kits/FidelityFX/framegeneration/include/dx12/ffx_api_framegeneration_dx12.h':'d533810bbd6fd4f87dfa2c1657c1457c7b1597b66345827d375b081d67127f66',
    'Kits/FidelityFX/framegeneration/include/ffx_framegeneration.h':'e6c42f8a38aab2c7c4fc6931545a8e5463fdf87349902ec9687d9fe4949a0566',
    'Kits/FidelityFX/framegeneration/include/ffx_framegeneration_api_types.h':'396596af3df63310674e8036abd2ad0fcd061e61334e7a2c76653a2be3c686b4',
    'Kits/FidelityFX/signedbin/amd_fidelityfx_framegeneration_dx12.dll':'02297beedd285e822d3a64f314cf00faf378dcec0edc47ff0c4dd71b3a8c2f18',
    'Kits/FidelityFX/signedbin/amd_fidelityfx_loader_dx12.dll':'e2d85aa05a9bd9ed8b38935fdf5199372cca6f74c12015143bb6f945ee1608aa',
    'Kits/FidelityFX/signedbin/amd_fidelityfx_upscaler_dx12.dll':'d0dcccc74a43c44ba435b7a369b456e0970d8a4464e4bd683119b374f2c9fb46',
    'Kits/FidelityFX/upscalers/include/ffx_upscale.h':'65be36d5653eb71c10379e0204f7bb7cd6a8aeec96e6f8cffc5f59ffeb1f89bf',
}
# The engine checks these same hashes before it loads the DLLs.
DLLS=('amd_fidelityfx_loader_dx12.dll','amd_fidelityfx_upscaler_dx12.dll','amd_fidelityfx_framegeneration_dx12.dll')
NOTICES=('Kits/FidelityFX/docs/license.md','3rdpartynotice.md')
AGILITY='1.618.5'
AGILITY_URL=f'https://www.nuget.org/api/v2/package/Microsoft.Direct3D.D3D12/{AGILITY}'
AGILITY_SHA256='0027fc24f947c48dbded13ada7d280be221eb651644e23a8a476f0f1f0a079dd'
AGILITY_CORE_SHA256='560f9574372a52ab66ad95ee1222f1eb4c9f6161d8f6b7b025d89f684b07246c'
AGILITY_FILES={'build/native/bin/x64/D3D12Core.dll':'x86_64/D3D12Core.dll','LICENSE.txt':'licenses/LICENSE.txt','LICENSE-CODE.txt':'licenses/LICENSE-CODE.txt'}

def digest(path):
    with path.open('rb') as data:return hashlib.file_digest(data,'sha256').hexdigest()

def fetch(url,path,expected,what):
    if not path.exists():
        path.parent.mkdir(parents=True,exist_ok=True)
        partial=path.with_name(path.name+'.partial')
        with urllib.request.urlopen(url,timeout=120) as source,partial.open('wb') as target:shutil.copyfileobj(source,target)
        partial.replace(path)
    if digest(path)!=expected:raise ValueError(what+' checksum mismatch: '+path.name)

def prepare(output,engine=None):
    for name,expected in FILES.items():fetch(BASE+name,output/name,expected,'AMD FidelityFX SDK')
    archive=output/f'Microsoft.Direct3D.D3D12.{AGILITY}.nupkg'
    fetch(AGILITY_URL,archive,AGILITY_SHA256,'DirectX Agility SDK')
    with zipfile.ZipFile(archive) as package:
        for member,target in AGILITY_FILES.items():
            path=output/'agility'/target;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(package.read(member))
    if digest(output/'agility/x86_64/D3D12Core.dll')!=AGILITY_CORE_SHA256:raise ValueError('DirectX Agility runtime checksum mismatch')
    if engine:
        for name in FILES:
            if not name.endswith('.h'):continue
            target=engine/'thirdparty/amd-fsr-sdk'/name.removeprefix('Kits/FidelityFX/')
            target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(output/name,target)
        # MinGW's d3d12.h returns GetDesc's structure through a pointer.
        header=engine/'thirdparty/amd-fsr-sdk/api/include/dx12/ffx_api_dx12.h'
        text=header.read_text();original='D3D12_RESOURCE_DESC desc = pRes->GetDesc();'
        if text.count(original)!=1:raise ValueError('Unexpected SDK resource helper; review the MinGW compatibility fix')
        header.write_text(text.replace(original,'#ifdef __MINGW32__\n    D3D12_RESOURCE_DESC desc;\n    pRes->GetDesc(&desc);\n#else\n    D3D12_RESOURCE_DESC desc = pRes->GetDesc();\n#endif'))
    print(f'Verified AMD FidelityFX SDK {VERSION} and DirectX Agility SDK {AGILITY}: {output}')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=pathlib.Path,required=True,help='An external directory; files are downloaded into it when missing')
    p.add_argument('--engine',type=pathlib.Path,help='Patched Godot 4.7 source tree')
    args=p.parse_args()
    prepare(args.output.resolve(),args.engine.resolve() if args.engine else None)
