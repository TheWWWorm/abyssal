/* Exercise Android chunk transport without a proprietary game fixture. */
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const code=fs.readFileSync(require('node:path').join(__dirname,'../android/import.js'),'utf8');
const bootstrap=fs.readFileSync(require('node:path').join(__dirname,'../android/bootstrap.js'),'utf8');
function startup(options={}){
 const loaded=[],failures=[],listeners={};let started=false;
 const context={URL,WebAssembly:options.noWasm?undefined:options.oldWasm?{}:WebAssembly,BigInt,BigInt64Array,
  location:{href:'https://abyssal.invalid/index.html',origin:'https://abyssal.invalid'},
  navigator:{userAgent:'Mozilla/5.0 Chrome/78.0.3904.108 Android'},
  console:{error(){},info(){}},AbyssalNative:{progress(){},failed(s){failures.push(s);}},
  addEventListener(type,callback){listeners[type]=callback;},
  document:{createElement(){return {};},head:{appendChild(script){
   loaded.push(script.src);
   if(script.src===options.failFile){script.onerror();return;}
   if(script.src===options.parseFile){listeners.error({filename:context.location.origin+'/'+script.src,message:'Unexpected token ?',error:Error('parse failure')});}
   else if(script.src!==options.noGlobal){
    if(script.src.endsWith('/pyodide.js'))context.loadPyodide=()=>{};
    else if(script.src==='vendor/amrnb.js')context.AMR={toWAV(){}};
    else if(script.src==='audio.js')context.AbyssalAudio={midiWav(){}};
    else if(script.src==='import.js')started=true;
   }
   script.onload();
  }}}};
 if(options.oldSyntax)context.Function=function(){throw SyntaxError('Unsupported syntax');};
 context.window=context;
 vm.runInNewContext(bootstrap,context);
 return {loaded,failures,listeners,started,runtime:context.AbyssalImporterRuntime};
}
function startupChecks(){
 for(const options of [{},{oldSyntax:true},{oldWasm:true},{oldSyntax:true,oldWasm:true}]){
  const result=startup(options),directory=options.oldSyntax||options.oldWasm?'vendor-compat/':'vendor/';
  assert.equal(result.failures.length,0);assert.equal(result.started,true);
  assert.equal(result.runtime.indexURL,'https://abyssal.invalid/'+directory);
  assert.deepEqual(result.loaded,[directory+'pyodide.js','vendor/amrnb.js','audio.js','import.js']);
 }
 const unsupported=startup({noWasm:true});assert.equal(unsupported.started,false);assert.equal(unsupported.loaded.length,0);
 assert.match(unsupported.failures[0],/WebView.*JAR converter/);
 for(const failure of [{failFile:'vendor-compat/pyodide.js'},{parseFile:'vendor-compat/pyodide.js'},{noGlobal:'vendor-compat/pyodide.js'}]){
  const result=startup({oldSyntax:true,...failure});
  assert.equal(result.started,false);assert.equal(result.loaded.length,1);assert.equal(result.failures.length,1);
  assert.match(result.failures[0],/Chromium 78\.0\.3904\.108/);assert.doesNotMatch(result.failures[0],/\.abyss/);
 }
 const runtimeFailure=startup({oldWasm:true});
 const event={filename:'https://abyssal.invalid/vendor-compat/pyodide.asm.js',message:'Synthetic runtime failure'};
 runtimeFailure.listeners.error(event);runtimeFailure.listeners.error(event);
 assert.equal(runtimeFailure.failures.length,1);assert.match(runtimeFailure.failures[0],/Synthetic runtime failure/);
}
async function run(fail=false,directory='vendor/'){
 const output=Uint8Array.from({length:500003},(_,i)=>(i*17)%256),chunks=[];
 let began=false,complete=false,failure='',decoded=false;
 const context={URL,location:{href:'https://abyssal.invalid/index.html'},Uint8Array,JSON,String,Math,console:{error(){}},
  AbyssalImporterRuntime:{indexURL:'https://abyssal.invalid/'+directory},
  btoa:s=>Buffer.from(s,'binary').toString('base64'),
  fetch:async()=>({arrayBuffer:async()=>new ArrayBuffer(4)}),
  loadPyodide:async options=>{assert.equal(options.indexURL,context.AbyssalImporterRuntime.indexURL);assert.equal(options.fullStdLib,false);return {unpackArchive(bytes){assert.ok(bytes instanceof Uint8Array);},globals:{set(){}},FS:{writeFile(){},readFile(){return output;}},
   runPython(source){if(source.includes('json.dumps(decode')){decoded=true;if(fail)throw Error('Traceback (most recent call last):\nclass_data.DataError: Unsupported synthetic JAR');return '[]';}}};},
  AbyssalNative:{progress(){},begin(){began=true;},chunk(s){assert.ok(began);assert.ok(s.length<=400000);chunks.push(Buffer.from(s,'base64'));},
   complete(){complete=true;},failed(s){failure=s;}}};
 await vm.runInNewContext(code,context);
 assert.ok(decoded);
 if(fail){assert.equal(complete,false);assert.equal(began,false);assert.equal(failure,'class_data.DataError: Unsupported synthetic JAR');}
 else{assert.equal(failure,'');assert.ok(complete);assert.equal(chunks.length,3);assert.deepEqual(Buffer.concat(chunks),Buffer.from(output));}
}
(async()=>{startupChecks();for(const directory of ['vendor/','vendor-compat/']){await run(false,directory);await run(true,directory);}console.log('Android importer: automatic runtime selection, startup failures, multi-chunk round trip and decoder failure passed');})().catch(e=>{console.error(e);process.exitCode=1;});
