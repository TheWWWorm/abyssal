/* Write a subset of an OpenType font holding only the given characters.
 *   node subset_font.js <harfbuzz-subset.wasm> <font.otf|.ttc> <face index> <characters file> <output>
 * harfbuzz-subset.wasm comes from the harfbuzzjs npm package. Only
 * tools/engine_text.py runs this, when it prepares the CJK interface fonts. */
'use strict';
const fs=require('node:fs');
(async()=>{
  const [wasm,font,index,charactersFile,output]=process.argv.slice(2);
  const module=await WebAssembly.compile(fs.readFileSync(wasm));
  const imports={};
  for(const entry of WebAssembly.Module.imports(module)){imports[entry.module]??={};imports[entry.module][entry.name]=()=>{throw Error('Unexpected import '+entry.name)}}
  const {exports:hb}=await WebAssembly.instantiate(module,imports);
  const heap=()=>new Uint8Array(hb.memory.buffer);
  const data=fs.readFileSync(font);
  const pointer=hb.malloc(data.length);heap().set(data,pointer);
  const face=hb.hb_face_create(hb.hb_blob_create(pointer,data.length,2,0,0),Number(index));
  const input=hb.hb_subset_input_create_or_fail();
  const unicodes=hb.hb_subset_input_unicode_set(input);
  for(const character of new Set(fs.readFileSync(charactersFile,'utf8')))hb.hb_set_add(unicodes,character.codePointAt(0));
  const subset=hb.hb_subset_or_fail(face,input);
  if(!subset)throw Error('Subsetting failed');
  const blob=hb.hb_face_reference_blob(subset);
  const start=hb.hb_blob_get_data(blob,0);
  fs.writeFileSync(output,heap().slice(start,start+hb.hb_blob_get_length(blob)));
})().catch(error=>{console.error(error.message);process.exit(1)});
