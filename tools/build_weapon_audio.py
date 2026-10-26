#!/usr/bin/env python3
"""Prepare equipment-specific underwater discharges from credited recordings.

FFmpeg, NumPy and SciPy are required. Download the hash-pinned sources listed in
provenance/weapon-audio.json to --sources. Original recordings are not bundled.
The game mixes use the Pixabay Content License and CC0 hydrophone material.
"""
import argparse
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import subprocess
import wave
import numpy as np
from scipy import signal

ROOT=Path(__file__).resolve().parents[1]
RATE=48000

def layer(source, length, gain=1, *, start=.022, speed=1., high=55, low=14000, at=0., release=.12, attack=.002):
    return dict(source=source,length=length,gain=gain,start=start,speed=speed,high=high,low=low,at=at,release=release,attack=attack)

def shots(prefix, takes):return [f'{prefix}-{n:02}.mp3' for n in takes]

# Preserve the designed discharge body and its spectral movement. The faster
# weapons trim only the quiet tail; slow coils retain a longer field release.
# Every take has a different principal recording, rather than a pitch randomizer.
RECIPES={
 'gun':dict(equipment=0,duration=.82,rms=.19,layers=[layer(shots('pulse-tm',[1,2,3]),.80,.86),layer(shots('plasma-ku',[4,2,3]),.44,.18,high=1800,at=.012)]),
 'gun-ii':dict(equipment=1,duration=.73,rms=.20,layers=[layer(shots('pulse-tm',[2,3,5]),.78,.90,speed=1.08),layer(shots('plasma-ku',[2,3,4]),.40,.20,high=1500,at=.008)]),
 'gun-iii':dict(equipment=2,duration=.98,rms=.21,single_decay=.27,layers=[layer(shots('pulse-dn',[1,3,4]),.94,.85,start=[.265,.325,.245],speed=1.03),layer(shots('pulse-tm',[4,5,1]),.68,.18,start=[.22,.34,.24],high=1400,attack=.015)]),
 'beam':dict(equipment=3,duration=1.28,rms=.20,layers=[layer(shots('plasma-pp',[1,2,5]),1.22,.80),layer(shots('pulse-tm',[1,3,5]),.75,.36,high=1200,at=.006)]),
 'beam-ii':dict(equipment=4,duration=1.52,rms=.22,layers=[layer(shots('plasma-pp',[2,5,1]),1.28,.82,speed=.90),layer(shots('pulse-dn',[2,4,3]),1.30,.38,low=5000,at=.018)]),
 'beam-iii':dict(equipment=5,duration=1.65,rms=.22,single_decay=.47,layers=[layer(shots('plasma-pp',[5,2,1]),1.22,.84,start=[.145,.195,.165],speed=.82),layer(shots('pulse-dn',[3,4,2]),1.0,.38,start=[.325,.245,.405],speed=.86,low=1300,attack=.018)]),
 'plasma':dict(equipment=6,duration=.65,rms=.18,layers=[layer(shots('plasma-ku',[1,3,5]),.66,.90),layer(shots('plasma-pp',[4,3,1]),.57,.17,speed=1.08,at=.012)]),
 'plasma-ii':dict(equipment=7,duration=.55,rms=.19,layers=[layer(shots('plasma-ku',[2,4,3]),.60,.92,speed=1.10),layer(shots('plasma-pp',[3,4,2]),.46,.20,high=500,at=.009)]),
 'plasma-iii':dict(equipment=8,duration=.68,rms=.21,layers=[layer(shots('plasma-ku',[5,1,3]),.66,.85,speed=.98),layer(shots('plasma-pp',[5,2,1]),.63,.30,low=7800,at=.009)]),
 'mass':dict(equipment=9,duration=.88,rms=.20,layers=[layer(shots('pulse-dn',[5,1,2]),.85,.86,low=10000),layer(shots('pulse-tm',[3,2,1]),.65,.23,high=500,at=.005)]),
 'mass-ii':dict(equipment=10,duration=.68,rms=.21,layers=[layer(shots('pulse-dn',[1,5,4]),.73,.88,speed=1.10,low=11000,release=.16),layer(shots('plasma-ku',[2,4,3]),.45,.23,high=1500)]),
 'mass-iii':dict(equipment=11,duration=1.00,rms=.23,layers=[layer(shots('pulse-dn',[4,3,2]),.98,.90,speed=.96,low=8500),layer(shots('pulse-tm',[4,5,1]),.72,.26,high=700,at=.008)]),
 'torpedo':dict(equipment=12,duration=1.30,rms=.16,layers=[layer('underwater-swish.mp3',1.20,.86,start=.045,high=100,low=6500,attack=.006,release=.36),layer('underwater-deep.mp3',.95,.23,start=.94,low=1300,attack=.020,release=.40),layer('water.mp3',1.08,.22,start=23.1,high=450,low=4800,at=.05,attack=.04,release=.42)]),
 'torpedo-ii':dict(equipment=13,duration=1.60,rms=.18,layers=[layer('underwater-deep.mp3',1.40,.72,start=.94,high=70,low=5000,attack=.015,release=.45),layer('underwater-swish.mp3',1.25,.38,start=.065,high=1100,low=6800,speed=1.05,release=.35),layer('water.mp3',1.36,.24,start=24.0,high=350,low=5000,at=.06,attack=.055,release=.45)]),
 'torpedo-iii':dict(equipment=14,duration=1.95,rms=.21,layers=[layer('underwater-deep.mp3',1.65,.90,start=.94,speed=.82,high=45,low=3900,attack=.012,release=.50),layer('underwater-swish.mp3',1.60,.33,start=.045,high=900,low=6000,release=.55),layer('water.mp3',1.75,.26,start=23.5,high=250,low=5500,at=.06,attack=.05,release=.55)]),
 'eclipse':dict(equipment=42,duration=1.42,rms=.24,layers=[layer(shots('pulse-dn',[3,4,2]),1.30,.78,speed=.95),layer(shots('plasma-pp',[2,5,1]),1.20,.57,speed=.94,at=.012),layer(shots('pulse-tm',[4,1,5]),.64,.18,high=2000)]),
}

def fade(x,attack,release):
    x=x.copy();a=min(len(x),round(attack*RATE));r=min(len(x),round(release*RATE))
    if a:x[:a]*=np.sin(np.linspace(0,np.pi/2,a))**2
    if r:x[-r:]*=np.sin(np.linspace(np.pi/2,0,r))**2
    return x

def single_discharge(x,decay):
    """Remove the source's second swell while retaining its changing spectrum.

    The principal body starts at the first full discharge, not its pre-click.
    A smooth RMS follower and falling envelope prevent another perceived shot;
    no echo, repeated attack or oscillator is added.
    """
    from scipy.ndimage import gaussian_filter1d
    rms=np.sqrt(gaussian_filter1d(x*x,RATE*.012)+1e-10)
    target=np.exp(-np.arange(len(x))/(RATE*decay))
    # Preserve quiet gaps and the original fine texture; never amplify > 3x.
    gain=np.minimum(3.0,.22*target/np.maximum(rms,.0001))
    return fade(x*gain,.004,.16)

def build(sources,output,ffmpeg):
    inv=json.loads((ROOT/'provenance/weapon-audio.json').read_text());inputs={}
    for source in inv['sources']:
        path=sources/source['filename']
        if hashlib.sha256(path.read_bytes()).hexdigest()!=source['sha256']:raise ValueError('Changed source: '+str(path))
        b=subprocess.check_output([ffmpeg,'-v','error','-i',str(path),'-ar',str(RATE),'-ac','2','-f','f32le','-'])
        inputs[source['filename']]=np.frombuffer(b,'<f4').reshape(-1,2).mean(axis=1).astype(float)
    output.mkdir(parents=True,exist_ok=True);records=[]
    for bank,recipe in RECIPES.items():
        for take in range(3):
            mix=np.zeros(round(recipe['duration']*RATE))
            for spec in recipe['layers']:
                name=spec['source'][take] if isinstance(spec['source'],list) else spec['source']
                start=spec['start'][take] if isinstance(spec['start'],list) else spec['start']
                start+=([0,.17,.31][take] if name in ('water.mp3','underwater-deep.mp3') else [0,.006,.012][take] if name=='underwater-swish.mp3' else 0)
                x=inputs[name][round(start*RATE):round((start+spec['length'])*RATE)]
                ratio=Fraction(1/spec['speed']).limit_denominator(1000)
                if ratio!=1:x=signal.resample_poly(x,ratio.numerator,ratio.denominator)
                x=signal.sosfilt(signal.butter(2,[spec['high'],spec['low']],btype='bandpass',fs=RATE,output='sos'),x)
                x=fade(x,spec['attack'],spec['release'])
                x*=spec['gain']/max(.00001,np.max(np.abs(x)))
                at=round(spec['at']*RATE);n=min(len(x),len(mix)-at);mix[at:at+n]+=x[:n]
            if 'single_decay' in recipe:
                mix=single_discharge(mix,recipe['single_decay'])
            # Short, quiet diffusion binds the layered discharges into one event.
            # It is a tail, not a second impact or a synthetic pitch sweep.
            dry=mix.copy()
            for delay,gain in ([] if 'single_decay' in recipe else [(0.027,.065),(.043,.035)]):
                n=round(delay*RATE);mix[n:]+=dry[:-n]*gain
            mix=fade(mix,.001,.12)
            window=np.sin(np.linspace(0,np.pi,len(mix)))**2
            mix-=mix.sum()/window.sum()*window
            mix*=min(.72/max(.00001,np.max(np.abs(mix))),recipe['rms']/max(.00001,np.sqrt(np.mean(mix*mix))))
            pcm=np.rint(mix*32767).astype('<i2');pcm[0]=pcm[-1]=0
            path=output/f'{bank}-{take+1}.wav'
            with wave.open(str(path),'wb') as w:w.setnchannels(1);w.setsampwidth(2);w.setframerate(RATE);w.writeframes(pcm.tobytes())
            records.append(dict(path='game/audio/weapons/'+path.name,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),bytes=path.stat().st_size,equipment_id=recipe['equipment']))
    return sorted(records,key=lambda r:r['path'])

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--sources',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--ffmpeg',default='ffmpeg');a=p.parse_args()
    print(json.dumps(build(a.sources,a.output,a.ffmpeg),indent=2))
