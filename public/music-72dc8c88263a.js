/* Engine-authored music transport. Owner-imported PCM, or an owner-supplied
 * replacement file the browser decodes, stays in memory; no fetch.
 * Keep one decoded buffer per track and use the audio clock, not game frames.
 * Short effects remain on Godot's sample player. */
(function(scope) {
  'use strict';
  class Music {
    constructor(context) {
      this.context=context;this.buffers=new Map();this.pending=new Map();this.source=null;
      this.key='';this.offset=0;this.started=0;this.paused=true;
      this.gain=context.createGain();this.gain.connect(context.destination);
      this.unlock=()=>{if(!this.paused)this.context.resume().catch(()=>{});};
      scope.addEventListener?.('pointerdown',this.unlock);
      scope.addEventListener?.('keydown',this.unlock);
    }
    prepare(key,base64,rate,stereo) {
      if(this.buffers.has(key))return;
      const raw=atob(base64),channels=stereo?2:1;
      if(raw.length%(channels*2)||rate<=0)throw Error('Invalid music PCM');
      const frames=raw.length/(channels*2),buffer=this.context.createBuffer(channels,frames,rate);
      for(let channel=0;channel<channels;channel++) {
        const samples=buffer.getChannelData(channel);
        for(let frame=0;frame<frames;frame++) {
          const index=(frame*channels+channel)*2;
          let value=raw.charCodeAt(index)|(raw.charCodeAt(index+1)<<8);
          if(value>=32768)value-=65536;
          samples[frame]=value/32768;
        }
      }
      this.buffers.set(key,buffer);
    }
    prepareEncoded(key,base64) {
      // OGG, MP3 or WAV bytes. Decoding is asynchronous: until it finishes the
      // track stays silent, and play() starts it on the next update.
      if(this.buffers.has(key)||this.pending.has(key))return;
      const raw=atob(base64),bytes=new Uint8Array(raw.length);
      for(let i=0;i<raw.length;i++)bytes[i]=raw.charCodeAt(i);
      const token={};this.pending.set(key,token);
      this.context.decodeAudioData(bytes.buffer).then(buffer=>{
        if(this.pending.get(key)!==token)return;
        this.pending.delete(key);this.buffers.set(key,buffer);
        if(key===this.key&&!this.paused)this.play();
      },()=>{if(this.pending.get(key)===token)this.pending.delete(key);});
    }
    forget(key) {
      if(key===this.key)this.stop();
      this.buffers.delete(key);this.pending.delete(key);
    }
    has(key) {return this.buffers.has(key)||this.pending.has(key);}
    update(key,volume,paused) {
      if(key!==this.key){this.stop();this.key=key;}
      this.gain.gain.setTargetAtTime(Math.max(0,Math.min(1,volume)),this.context.currentTime,.01);
      this.paused=paused;
      if(paused)this.pause();else this.play();
    }
    pause() {
      if(!this.source)return;
      this.offset=(this.offset+this.context.currentTime-this.started)%this.source.buffer.duration;
      this.source.stop();this.source.disconnect();this.source=null;
    }
    play() {
      if(this.source||!this.buffers.has(this.key))return;
      const source=this.context.createBufferSource();source.buffer=this.buffers.get(this.key);
      source.loop=true;source.connect(this.gain);
      this.started=this.context.currentTime;source.start(0,this.offset);this.source=source;
      this.unlock();
    }
    stop() {this.pause();this.offset=0;this.paused=true;}
    dispose() {
      this.stop();this.buffers.clear();this.pending.clear();this.gain.disconnect();
      scope.removeEventListener?.('pointerdown',this.unlock);
      scope.removeEventListener?.('keydown',this.unlock);
      this.context.close().catch(()=>{});
    }
  }
  scope.AbyssalMusic={Music,create:()=>new Music(new (scope.AudioContext||scope.webkitAudioContext)())};
})(globalThis);
