"""The only recorded audio shipped by the engine, separate from imported DEEP content."""
import hashlib
import io
import json
import wave
from paths import ROOT

AUDIO = frozenset('game/audio/weapons/%s-%d.wav' % (kind, variant)
                  for kind in ('gun', 'gun-ii', 'gun-iii', 'beam', 'beam-ii', 'beam-iii',
                               'plasma', 'plasma-ii', 'plasma-iii', 'mass', 'mass-ii', 'mass-iii',
                               'torpedo', 'torpedo-ii', 'torpedo-iii', 'eclipse')
                  for variant in range(1, 4))


def verify_audio(path, name):
    verify_audio_payload(path.read_bytes(), name)


def verify_audio_payload(payload, name):
    if name not in AUDIO:
        raise ValueError('Unreviewed engine audio: '+name)
    inventory = json.loads((ROOT/'provenance/weapon-audio.json').read_text())
    entries = {row['path']: row for row in inventory['assets']}
    if set(entries) != AUDIO:
        raise ValueError('Weapon audio inventory differs from its explicit allowlist')
    row = entries[name]
    if len(payload) != row['bytes'] or hashlib.sha256(payload).hexdigest() != row['sha256']:
        raise ValueError('Weapon audio changed since its provenance inventory: '+name)
    with wave.open(io.BytesIO(payload), 'rb') as sound:
        if (sound.getnchannels(), sound.getsampwidth(), sound.getframerate()) != (1, 2, 48000):
            raise ValueError('Unexpected weapon audio encoding: '+name)
        if not 0 < sound.getnframes() <= 120000:
            raise ValueError('Unexpected weapon audio duration: '+name)
