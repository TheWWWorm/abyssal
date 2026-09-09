/* The Web and Android builds run the same decoder and audio conversion. */
'use strict';
(async () => {
  const progress = message => AbyssalNative.progress(message);
  try {
    progress('Loading the bundled offline importer…');
    const py = await loadPyodide({indexURL:new URL('vendor/', location.href).href});
    py.unpackArchive(await (await fetch('sources.zip')).arrayBuffer(), 'zip', {extractDir:'/importer'});
    py.FS.writeFile('/game.jar', new Uint8Array(await (await fetch('game.jar')).arrayBuffer()));
    py.globals.set('report_progress', progress);
    const audio = JSON.parse(py.runPython(`import sys, json
sys.path.insert(0, '/importer')
from import_jar import decode, pack
json.dumps(decode('/game.jar', '/content', report_progress))`));
    for (const [i, path] of audio.entries()) {
      progress(`Converting audio: ${i+1} / ${audio.length}`);
      const bytes = py.FS.readFile('/content/'+path);
      const wav = path.endsWith('.mid') ? AbyssalAudio.midiWav(bytes) : AMR.toWAV(bytes);
      if (!wav || wav.length<44) throw Error('Could not decode audio: '+path);
      py.FS.writeFile('/content/'+path+'.wav', wav);
    }
    progress('Preparing your local game content…');
    py.runPython(`from pathlib import Path
Path('/ready.abyss').write_bytes(pack('/content'))`);
    const bytes = py.FS.readFile('/ready.abyss');
    AbyssalNative.begin();
    for (let offset=0; offset<bytes.length; offset+=196608) {
      let binary='';
      const end=Math.min(bytes.length,offset+196608);
      for(let start=offset; start<end; start+=8192)
        binary+=String.fromCharCode(...bytes.subarray(start, Math.min(end,start+8192)));
      AbyssalNative.chunk(btoa(binary));
    }
    AbyssalNative.complete();
  } catch(error) { AbyssalNative.failed(String(error.message||error)); }
})();
