/* JAR bytes and converted resources stay in this worker and Godot's local storage.
 * All dependencies are self-hosted; there is no upload or conversion endpoint. */
'use strict';
const progress = message => postMessage({type:'progress',message});
self.onmessage = async ({data}) => {
  try {
    if (!(data instanceof ArrayBuffer) || data.byteLength>16*1024*1024)throw Error('JAR exceeds 16 MiB.');
    progress('Loading local importer…');
    importScripts('vendor/pyodide.js','vendor/amrnb.js','audio.js');
    const py=await loadPyodide({indexURL:new URL('vendor/',self.location.href).href});
    const response=await fetch('sources.zip');
    if(!response.ok)throw Error('Importer files are missing. Re-export the complete Web build.');
    py.unpackArchive(await response.arrayBuffer(),'zip',{extractDir:'/importer'});
    py.FS.writeFile('/game.jar',new Uint8Array(data));
    py.globals.set('report_progress',progress);
    const audio=py.runPython(`import sys, json
sys.path.insert(0, '/importer')
from import_jar import decode, pack
json.dumps(decode('/game.jar', '/content', report_progress))`);
    for(const [i,path] of JSON.parse(audio).entries()){
      progress('Converting audio: '+(i+1)+' / '+JSON.parse(audio).length);
      const bytes=py.FS.readFile('/content/'+path);
      const wav=path.endsWith('.mid')?AbyssalAudio.midiWav(bytes):AMR.toWAV(bytes);
      if(!wav||wav.length<44)throw Error('Could not decode audio: '+path);
      py.FS.writeFile('/content/'+path+'.wav',wav);
    }
    progress('Preparing browser content cache…');
    py.runPython(`from pathlib import Path
Path('/ready.abyss').write_bytes(pack('/content'))`);
    const result=py.FS.readFile('/ready.abyss');
    postMessage({type:'complete',buffer:result.buffer},[result.buffer]);
  } catch(error) {
    console.error('Local JAR import failed:',error);
    postMessage({type:'error',message:String(error.message||error)});
  }
};
