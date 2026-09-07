/* Synthetic MIDI timing/running-status regression; no original compositions. */
'use strict';
const assert=require('node:assert/strict');require('../browser/audio.js');
const track=[0,0xC0,10,0,0x90,60,100,0x60,60,0,0,0xFF,0x51,3,0x0F,0x42,0x40,0,0x90,62,100,0x60,0x80,62,0,0,0xFF,0x2F,0];
function file(events){return new Uint8Array([77,84,104,100,0,0,0,6,0,0,0,1,0,96,77,84,114,107,0,0,0,events.length,...events]);}
const result=AbyssalAudio.midiNotes(file(track));assert.equal(result.notes.length,2);
assert.equal(result.notes[0].end,.5);assert.equal(result.notes[1].start,.5);assert.equal(result.notes[1].end,1.5);
assert.equal(result.notes[0].program,10);
const wav=AbyssalAudio.midiWav(file(track)),view=new DataView(wav.buffer);
assert.equal(view.getUint32(24,true),22050);assert.equal(view.getUint16(22,true),2);
assert.equal(view.getUint32(40,true),wav.length-44);assert(wav.slice(44).some(x=>x!==0));
assert.throws(()=>AbyssalAudio.midiNotes(file(track).slice(0,-3)),/Truncated/);
const sustain=AbyssalAudio.midiNotes(file([0,0xB0,64,127,0,0x90,60,100,96,0x80,60,0,96,0xB0,64,0,0,255,47,0]));
assert.equal(sustain.notes[0].end,1);
console.log('Browser MIDI checks passed (tempo, running status, sustain, PCM and truncation).');

require('../browser/music.js');
class AudioClock {
 constructor(){this.currentTime=0;this.buffers=[];this.sources=[];this.active=0;this.closed=false;}
 createGain(){return {gain:{setTargetAtTime(){}},connect(){},disconnect(){}};}
 createBuffer(channels,frames,rate){
  const data=Array.from({length:channels},()=>new Float32Array(frames));
  const buffer={duration:frames/rate,getChannelData:i=>data[i]};this.buffers.push(buffer);return buffer;
 }
 createBufferSource(){
  const clock=this,source={connect(){},disconnect(){},start(time,offset){this.offset=offset;clock.active++;},stop(){clock.active--;}};
  this.sources.push(source);return source;
 }
 resume(){return Promise.resolve();}
 close(){this.closed=true;return Promise.resolve();}
}
const clock=new AudioClock(),music=new AbyssalMusic.Music(clock);
const pcm=Buffer.alloc(16);pcm.writeInt16LE(16384,2);pcm.writeInt16LE(-32768,4);
music.prepare('score',pcm.toString('base64'),4,false);
music.prepare('score',pcm.toString('base64'),4,false);
assert.equal(clock.buffers.length,1);assert.equal(clock.buffers[0].getChannelData(0)[1],.5);
assert.equal(clock.buffers[0].getChannelData(0)[2],-1);
for(let i=0;i<600;i++)music.update('score',.4,false);
assert.equal(clock.sources.length,1);assert.equal(clock.active,1);assert(clock.sources[0].loop);
clock.currentTime=1.25;
for(let i=0;i<600;i++)music.update('score',.4,true);
assert.equal(clock.active,0);assert.equal(music.offset,1.25);
clock.currentTime=11.25;music.update('score',.4,false);
assert.equal(clock.sources[1].offset,1.25);
assert.equal(clock.sources[1].buffer,clock.sources[0].buffer,'Menus reuse the decoded music buffer');
clock.currentTime=11.75;music.update('score',.4,true);
clock.currentTime=30;music.update('score',.4,false);
assert.equal(clock.sources[2].offset,1.75,'Repeated menus exclude all paused time');
clock.currentTime=33;music.update('score',.4,true);
assert.equal(music.offset,.75,'Track position wraps using the audio clock without game updates');
music.stop();music.update('score',.4,false);assert.equal(clock.sources.at(-1).offset,0);
music.prepare('other',pcm.toString('base64'),4,false);music.update('other',.4,false);
assert.equal(clock.active,1,'Switching tracks stops the old source');assert.equal(music.offset,0);
music.dispose();assert.equal(clock.active,0);assert.equal(clock.closed,true);assert.equal(music.buffers.size,0);
console.log('Browser music checks passed (PCM, one buffer, pause/resume, real audio clock, loops and disposal).');
