/* Exercise Android chunk transport without a proprietary game fixture. */
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const code=fs.readFileSync(require('node:path').join(__dirname,'../android/import.js'),'utf8');
async function run(fail=false){
 const output=Uint8Array.from({length:500003},(_,i)=>(i*17)%256),chunks=[];
 let began=false,complete=false,failure='',decoded=false;
 const context={URL,location:{href:'https://abyssal.invalid/index.html'},Uint8Array,JSON,String,Math,
  btoa:s=>Buffer.from(s,'binary').toString('base64'),
  fetch:async()=>({arrayBuffer:async()=>new ArrayBuffer(4)}),
  loadPyodide:async()=>({unpackArchive(){},globals:{set(){}},FS:{writeFile(){},readFile(){return output;}},
   runPython(source){if(source.includes('json.dumps(decode')){decoded=true;if(fail)throw Error('Unsupported synthetic JAR');return '[]';}}}),
  AbyssalNative:{progress(){},begin(){began=true;},chunk(s){assert.ok(began);assert.ok(s.length<=400000);chunks.push(Buffer.from(s,'base64'));},
   complete(){complete=true;},failed(s){failure=s;}}};
 await vm.runInNewContext(code,context);
 assert.ok(decoded);
 if(fail){assert.equal(complete,false);assert.equal(began,false);assert.match(failure,/Unsupported synthetic JAR/);}
 else{assert.equal(failure,'');assert.ok(complete);assert.equal(chunks.length,3);assert.deepEqual(Buffer.concat(chunks),Buffer.from(output));}
}
(async()=>{await run();await run(true);console.log('Android transport: multi-chunk round trip and decoder failure passed');})().catch(e=>{console.error(e);process.exitCode=1;});
