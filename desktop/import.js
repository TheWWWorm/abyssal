/* Offline desktop entry point for the same portable converter as the Web build.
 * Only the pinned codec/runtime is executable. The selected JAR remains data. */
'use strict';
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
async function convert(jar,output,progressPath){
  const report=message=>{
    if(progressPath)fs.writeFileSync(progressPath,message,'utf8');
  };
  if(!jar||!output)throw Error('Expected a JAR path and output pack path.');
  if(fs.statSync(jar).size>16*1024*1024)throw Error('JAR exceeds 16 MiB.');
  const data=fs.readFileSync(jar);
  report('Loading the bundled offline importer…');
  const {loadPyodide}=require('./vendor/pyodide.js');
  const py=await loadPyodide({indexURL:path.join(__dirname,'vendor')+path.sep});
  py.unpackArchive(new Uint8Array(fs.readFileSync(path.join(__dirname,'sources.zip'))),'zip',{extractDir:'/importer'});
  py.FS.writeFile('/game.jar',new Uint8Array(data));py.globals.set('report_progress',report);
  const audio=JSON.parse(py.runPython(`import sys, json
sys.path.insert(0, '/importer')
from import_jar import decode, pack
json.dumps(decode('/game.jar', '/content', report_progress))`));
  // The unmodified upstream bundle exposes AMR as a script global.
  const codec={console,TextDecoder,TextEncoder,setTimeout,clearTimeout,process,require,module:{exports:{}},__dirname:path.join(__dirname,'vendor'),Buffer};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'vendor/amrnb.js'),'utf8'),codec,{filename:'amrnb.js'});
  require('./audio.js');
  for(const [i,name] of audio.entries()){
    report(`Converting audio: ${i+1} / ${audio.length}`);
    const bytes=py.FS.readFile('/content/'+name);
    const wav=name.endsWith('.mid')?globalThis.AbyssalAudio.midiWav(bytes):codec.AMR.toWAV(bytes);
    if(!wav||wav.length<44)throw Error('Could not decode audio: '+name);
    py.FS.writeFile('/content/'+name+'.wav',wav);
  }
  report('Preparing your local game content…');
  py.runPython("from pathlib import Path\nPath('/ready.abyss').write_bytes(pack('/content'))");
  const temporary=output+'.partial';
  try{
    fs.writeFileSync(temporary,py.FS.readFile('/ready.abyss'),{flag:'wx'});
    fs.renameSync(temporary,output);
  }finally{if(fs.existsSync(temporary))fs.unlinkSync(temporary);}
  console.log(output);
}
if(require.main===module)convert(...process.argv.slice(2)).catch(error=>{console.error(String(error.message||error));process.exitCode=1;});
module.exports={convert};
