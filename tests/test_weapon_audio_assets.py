"""Recorded engine audio has an explicit, hash-checked packaging boundary."""
import pathlib
import math
import struct
import sys
import tempfile
import unittest
import wave

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]/'tools'))
from paths import ROOT
from weapon_audio_assets import AUDIO, verify_audio
from export_game import stage_project


class WeaponAudioAssetTests(unittest.TestCase):
    def test_mk_iii_discharge_has_no_delayed_second_attack(self):
        for bank in ('gun-iii', 'beam-iii'):
            for take in range(1, 4):
                with self.subTest(bank=bank, take=take):
                    with wave.open(str(ROOT/f'game/audio/weapons/{bank}-{take}.wav')) as sound:
                        samples = struct.unpack('<'+'h'*sound.getnframes(), sound.readframes(sound.getnframes()))
                    # A second strong swell hundreds of milliseconds after the
                    # trigger sounded like another shot, particularly on MK III.
                    rms = [math.sqrt(sum(v*v for v in samples[i:i+2400])/2400)
                           for i in range(0, len(samples)-2400, 2400)]
                    self.assertLess(rms.index(max(rms)), 2)
                    self.assertLess(max(rms[3:]), max(rms[:2])*.80)

    def test_every_recorded_sample_is_verified_and_staged(self):
        with tempfile.TemporaryDirectory() as folder:
            stage = pathlib.Path(folder)
            stage_project(stage, 'linux')
            for name in AUDIO:
                verify_audio(ROOT/name, name)
                self.assertEqual((stage/pathlib.Path(name).relative_to('game')).read_bytes(), (ROOT/name).read_bytes())
                settings = (stage/pathlib.Path(name+'.import').relative_to('game')).read_text()
                self.assertIn('compress/mode=0', settings)
                self.assertIn('edit/loop_mode=0', settings)

    def test_added_or_modified_sound_cannot_enter_a_package(self):
        name = sorted(AUDIO)[0]
        with tempfile.TemporaryDirectory() as folder:
            sound = pathlib.Path(folder)/'sample.wav'
            sound.write_bytes((ROOT/name).read_bytes())
            with self.assertRaisesRegex(ValueError, 'Unreviewed engine audio'):
                verify_audio(sound, 'game/audio/weapons/unreviewed.wav')
            data = bytearray(sound.read_bytes()); data[-3] ^= 1
            sound.write_bytes(data)
            with self.assertRaisesRegex(ValueError, 'changed since its provenance'):
                verify_audio(sound, name)


if __name__ == '__main__':
    unittest.main()
