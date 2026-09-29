"""Synthesises the test clips in tool/test_audio/ (16 kHz mono PCM16).

    python3 tool/make_test_audio.py        # needs numpy

speech.wav is not made here: it is macOS text-to-speech,

    say -o tool/test_audio/speech.wav --data-format=LEI16@16000 \
      "Hello there. Can you find something in the house that rings? \
Let's go look in the kitchen together."

Synthetic sounds are a weak test of a sound classifier, and that is the
point of choosing these four: each is a sound whose *definition* is a
waveform (a whistle is a near-pure tone, a siren a swept one, a North
American ring is 440+480 Hz), so a model that recognises the real thing
should recognise these. sine.wav is the control.
"""
import wave

import numpy as np

SR = 16000
t = np.arange(SR * 4) / SR


def save(name, x):
    x = (np.clip(x, -1, 1) * 0.6 * 32767).astype('<i2')
    with wave.open(f'tool/test_audio/{name}.wav', 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(x.tobytes())


# Whistle: ~1.8 kHz with 5 Hz vibrato, the way a person whistles.
f = 1800 + 60 * np.sin(2 * np.pi * 5 * t)
ph = 2 * np.pi * np.cumsum(f) / SR
save('whistle', np.sin(ph) + 0.05 * np.sin(2 * ph))

# Siren: a wail sweeping 650-1500 Hz, 2 s a cycle, with harmonics.
f = 1075 + 425 * np.sin(2 * np.pi * 0.5 * t)
ph = 2 * np.pi * np.cumsum(f) / SR
save('siren', np.sin(ph) + 0.3 * np.sin(2 * ph) + 0.15 * np.sin(3 * ph))

# Telephone: 440+480 Hz, 1 s on / 0.5 s off, with a 20 Hz bell tremolo.
gate = ((t % 1.5) < 1.0).astype(float)
tremolo = 0.5 + 0.5 * np.sin(2 * np.pi * 20 * t)
save('telephone', gate * tremolo * (np.sin(2 * np.pi * 440 * t) + np.sin(2 * np.pi * 480 * t)) / 2)

# Control: a plain 1 kHz sine.
save('sine', np.sin(2 * np.pi * 1000 * t))
