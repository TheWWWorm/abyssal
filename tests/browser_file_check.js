/* Browser file picker lifetime and import races, using synthetic files only. */
'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const {test}=require('node:test');
const source=fs.readFileSync(path.join(__dirname,'../game/native/platform/file_access.gd'),'utf8');
const script=source.match(/JavaScriptBridge\.eval\("""([\s\S]*?)""",true\)/)[1];
const exitScript=source.match(/JavaScriptBridge\.eval\("(if\(window\.abyssalFiles\)[^\n]+)",true\)/)[1];

function setup() {
  const attached=new Set(), inputs=[], workers=[], events=[];
  const document={baseURI:'https://abyssal.invalid/game/',
    body:{appendChild(input){attached.add(input);}},
    createElement(tag){
      assert.equal(tag,'input');
      const input={files:[],remove(){attached.delete(this);},click(){
        // A native picker must have a document-owned input for its entire wait.
        assert.ok(attached.has(this),'file input must be attached before opening');
        assert.equal(this.hidden,true);
      }};
      inputs.push(input);return input;
    }};
  class Worker {
    constructor(url){this.url=String(url);workers.push(this);}
    postMessage(bytes,transfer){this.bytes=bytes;assert.equal(transfer[0],bytes);}
    terminate(){this.terminated=true;}
  }
  const context=vm.createContext({window:{},document,Worker,URL});
  vm.runInContext(script,context);
  const files=context.window.abyssalFiles;
  const callback=(...args)=>events.push(args);
  return {files,events,inputs,attached,workers,context,choose(){files.choose(callback);return inputs.at(-1);}};
}
function file(name='localized-DEEP.JAR',read=async()=>new ArrayBuffer(4)) {
  return {name,size:4,arrayBuffer:read};
}
async function select(input,chosen=file()) {input.files=[chosen];await input.onchange();}

test('selection keeps a live picker, then starts conversion and releases it',async()=>{
  const s=setup(), input=s.choose();
  assert.ok(s.attached.has(input));assert.equal(s.workers.length,0);
  await select(input);
  assert.equal(s.attached.size,0);assert.equal(input.onchange,null);
  assert.equal(s.events[0][0],'progress');assert.equal(s.files.busy,true);
  const worker=s.workers[0];assert.equal(worker.url,'https://abyssal.invalid/game/importer/worker.js');
  worker.onmessage({data:{type:'progress',message:'Converting'}});
  const buffer=new ArrayBuffer(8);worker.onmessage({data:{type:'complete',buffer}});
  assert.deepEqual(s.events.at(-1),['complete',buffer]);
  assert.equal(s.files.busy,false);assert.ok(worker.terminated);
});

test('cancel, empty selection and repeated opening clean up and allow a retry',async()=>{
  const s=setup(), cancelled=s.choose();cancelled.oncancel();
  assert.equal(s.attached.size,0);assert.equal(s.events.length,0);
  const abandoned=s.choose(), retry=s.choose();
  assert.equal(s.attached.size,1);assert.ok(s.attached.has(retry));assert.equal(abandoned.onchange,null);
  await retry.onchange();assert.equal(s.attached.size,0);
  await select(s.choose());assert.equal(s.workers.length,1);
});

test('private packs and selecting the same file again deliver the selected bytes',async()=>{
  const s=setup(), buffer=new ArrayBuffer(8), pack=file('private.ABYSS',async()=>buffer);
  await select(s.choose(),pack);await select(s.choose(),pack);
  assert.equal(s.workers.length,0);assert.equal(s.attached.size,0);
  assert.equal(s.events.filter(([type,value])=>type==='complete'&&value===buffer).length,2);
});

test('invalid, oversized and unreadable selections report errors and can be retried',async()=>{
  const s=setup();
  for(const chosen of [file('wrong.txt'),{...file(),size:16777217},file('read.jar',async()=>{throw Error('Cannot read file');})]){
    await select(s.choose(),chosen);
    assert.equal(s.events.at(-1)[0],'error');assert.equal(s.files.busy,false);
    assert.equal(s.attached.size,0);assert.equal(s.workers.length,0);
  }
  await select(s.choose());assert.equal(s.workers.length,1);
});

test('cancelling a pending read cannot start a worker or overwrite the next import',async()=>{
  const s=setup();let resolve;
  const pending=select(s.choose(),file('slow.jar',()=>new Promise(done=>{resolve=done;})));
  s.choose();assert.equal(s.events.at(-1)[0],'cancel');
  await select(s.choose(),file('ready.abyss'));
  const count=s.events.length;resolve(new ArrayBuffer(4));await pending;
  assert.equal(s.workers.length,0);assert.equal(s.events.length,count);assert.equal(s.files.busy,false);
});

test('cancelled worker messages cannot complete a newer import',async()=>{
  const s=setup();await select(s.choose());const old=s.workers[0];s.choose();
  assert.ok(old.terminated);await select(s.choose());
  const count=s.events.length;old.onmessage({data:{type:'complete',buffer:new ArrayBuffer(4)}});
  assert.equal(s.events.length,count);assert.equal(s.files.busy,true);assert.ok(!s.workers[1].terminated);
  s.workers[1].onerror();assert.equal(s.events.at(-1)[0],'error');assert.equal(s.files.busy,false);
});

test('leaving the game releases a pending picker and cancels conversion',async()=>{
  const s=setup(), input=s.choose();vm.runInContext(exitScript,s.context);
  assert.equal(s.attached.size,0);assert.equal(input.onchange,null);
  await select(s.choose());const worker=s.workers[0];vm.runInContext(exitScript,s.context);
  assert.ok(worker.terminated);assert.equal(s.files.busy,false);
  const count=s.events.length;worker.onmessage({data:{type:'complete',buffer:new ArrayBuffer(4)}});
  assert.equal(s.events.length,count);
});
