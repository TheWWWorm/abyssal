/* Small procedural MIDI renderer. Original engine code; no instrument samples.
 * SMF 0/1, PPQN/SMPTE timing, running status, tempo, program, sustain, volume,
 * expression and pan. Instruments approximate GM families; they are not a GM bank.
 * The user's MIDI composition is input data, never bundled with the engine. */
(function (scope) {
  'use strict';
  function midiNotes(bytes) {
    const data = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    let pos = 0;
    const need = n => { if (pos+n > bytes.length) throw Error('Truncated MIDI'); };
    const u8 = () => { need(1); return bytes[pos++]; };
    const u16 = () => { need(2); const v=data.getUint16(pos); pos+=2; return v; };
    const u32 = () => { need(4); const v=data.getUint32(pos); pos+=4; return v; };
    const tag = () => String.fromCharCode(u8(),u8(),u8(),u8());
    const vlq = () => { let value=0; for(let i=0;i<4;i++){const b=u8();value=value*128+(b&127);if(!(b&128))return value;}throw Error('Invalid MIDI length'); };
    if(tag()!=='MThd')throw Error('Invalid MIDI header');
    const length=u32(); if(length<6)throw Error('Invalid MIDI header length');
    const format=u16(), tracks=u16(), division=u16();
    if(format>1 || !tracks || tracks>128 || !division)throw Error('Unsupported MIDI format');
    need(length-6);pos+=length-6;
    const events=[];let order=0;
    for(let track=0;track<tracks;track++){
      if(tag()!=='MTrk')throw Error('Invalid MIDI track');
      const size=u32();need(size);const end=pos+size;let tick=0,running=0;
      while(pos<end){
        tick+=vlq();let status=u8();
        if(status<128){if(!running)throw Error('Missing MIDI running status');pos--;status=running;}
        if(status===255){
          const kind=u8(),count=vlq();need(count);
          if(kind===81 && count===3)events.push({tick,order:order++,tempo:bytes[pos]*65536+bytes[pos+1]*256+bytes[pos+2]});
          pos+=count;if(kind===47){pos=end;break;}
        }else if(status===240||status===247){running=0;const count=vlq();need(count);pos+=count;}
        else{
          if(status>=240)throw Error('Unsupported MIDI status');running=status;
          const kind=status>>4,a=u8(),b=(kind===12||kind===13)?0:u8();
          if(a>127||b>127)throw Error('Invalid MIDI data byte');
          events.push({tick,order:order++,channel:status&15,kind,a,b});
        }
        if(pos>end||events.length>200000)throw Error('MIDI exceeds limits');
      }
      events.push({tick,order:order++,end:true});
    }
    events.sort((a,b)=>a.tick-b.tick||a.order-b.order);
    const channels=Array.from({length:16},()=>({program:0,volume:100,expression:127,pan:64,sustain:false,active:new Map(),held:[]}));
    const notes=[];let tick=0,time=0,tempo=500000;
    const finish=(note,end)=>{note.end=Math.max(note.start+.01,end);notes.push(note);};
    const smpte=division&32768;
    const fps=smpte?256-(division>>8):0, rate=fps===29?30000/1001:fps;
    if(smpte && (![24,25,29,30].includes(fps)||!(division&255)))throw Error('Invalid SMPTE timing');
    for(const e of events){
      time+=(e.tick-tick)*(smpte?1/(rate*(division&255)):tempo/(division*1e6));tick=e.tick;
      if(time>300)throw Error('MIDI exceeds five-minute limit');
      if(e.tempo){tempo=e.tempo;continue;}if(e.end)continue;
      const c=channels[e.channel];
      if(e.kind===12)c.program=e.a;
      if(e.kind===11){
        if(e.a===7)c.volume=e.b; if(e.a===11)c.expression=e.b; if(e.a===10)c.pan=e.b;
        if(e.a===64){c.sustain=e.b>=64;if(!c.sustain){for(const n of c.held)finish(n,time);c.held=[];}}
        if(e.a===120||e.a===123){for(const list of c.active.values())for(const n of list)finish(n,time);c.active.clear();for(const n of c.held)finish(n,time);c.held=[];}
      }
      if(e.kind===9 && e.b){
        const note={start:time,key:e.a,velocity:e.b/127*c.volume/127*c.expression/127,pan:c.pan/127,program:c.program,drum:e.channel===9};
        const list=c.active.get(e.a)||[];list.push(note);c.active.set(e.a,list);
      }else if(e.kind===8||(e.kind===9&&!e.b)){
        const list=c.active.get(e.a);if(list&&list.length){const note=list.shift();if(c.sustain)c.held.push(note);else finish(note,time);}
      }
    }
    for(const c of channels){for(const list of c.active.values())for(const n of list)finish(n,time);for(const n of c.held)finish(n,time);}
    return {notes,duration:time+.45};
  }
  function midiWav(bytes) {
    const {notes,duration}=midiNotes(bytes),rate=22050,length=Math.ceil(duration*rate);
    const left=new Float32Array(length),right=new Float32Array(length);let operations=0;
    for(const note of notes){
      const family=note.program>>3,frequency=440*Math.pow(2,(note.key-69)/12);
      const start=Math.floor(note.start*rate),held=note.end-note.start;
      const release=note.drum?.12:.25,end=Math.min(length,Math.ceil((note.end+release)*rate));
      operations+=end-start;if(operations>120000000)throw Error('MIDI synthesis exceeds limits');
      const gain=.18*note.velocity,gl=Math.cos(note.pan*Math.PI/2)*gain,gr=Math.sin(note.pan*Math.PI/2)*gain;
      let random=(note.key+1)*1234567,phase=0;
      for(let i=start;i<end;i++){
        const t=(i-start)/rate;
        let envelope=Math.min(1,t/.008)*Math.min(1,Math.max(0,(held+release-t)/release)),sample;
        if(note.drum){
          random^=random<<13;random^=random>>>17;random^=random<<5;const noise=random/2147483648;
          const kick=note.key===35||note.key===36;
          envelope*=Math.exp(-t*(kick?18:28));sample=kick?Math.sin(2*Math.PI*(60*t+4*(1-Math.exp(-t*20)))):noise;
        }else{
          phase=2*Math.PI*frequency*t;
          // Smooth, band-limited additive timbres; avoid harsh aliased square waves.
          const overtone=frequency*3<rate*.45?Math.sin(phase*3):0;
          sample=Math.sin(phase)+(family===10?.12:family===7?.35:.22)*overtone;
          if(family===0||family===1||family===3)envelope*=.25+.75*Math.exp(-t*(family===3?5:2.5));
          if(family===5||family===6||family===11)envelope*=Math.min(1,t/.06);
        }
        left[i]+=sample*envelope*gl;right[i]+=sample*envelope*gr;
      }
    }
    let peak=1;for(let i=0;i<length;i++)peak=Math.max(peak,Math.abs(left[i]),Math.abs(right[i]));
    const result=new Uint8Array(44+length*4),view=new DataView(result.buffer);
    const text=(offset,value)=>{for(let i=0;i<value.length;i++)result[offset+i]=value.charCodeAt(i);};
    text(0,'RIFF');view.setUint32(4,result.length-8,true);text(8,'WAVEfmt ');view.setUint32(16,16,true);
    view.setUint16(20,1,true);view.setUint16(22,2,true);view.setUint32(24,rate,true);view.setUint32(28,rate*4,true);view.setUint16(32,4,true);view.setUint16(34,16,true);
    text(36,'data');view.setUint32(40,length*4,true);
    for(let i=0;i<length;i++){view.setInt16(44+i*4,Math.round(left[i]*30000/peak),true);view.setInt16(46+i*4,Math.round(right[i]*30000/peak),true);}
    return result;
  }
  scope.AbyssalAudio={midiNotes,midiWav};
})(globalThis);
