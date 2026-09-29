"""Runs the bundled YAMNet model over WAV files with desktop LiteRT, the same
windowing the Android plugin uses (15600 samples, 50% hop), and prints each
file's four strongest labels.

    pip install ai-edge-litert numpy
    python3 tool/classify_wav_yamnet.py tool/test_audio/*.wav

This checks the *model file and label list* the plugin ships. The Kotlin that
drives them on a device is checked by the instrumented test in
android/src/androidTest.
"""
import sys
import wave

import numpy as np
from ai_edge_litert.interpreter import Interpreter

ASSETS = 'android/src/main/assets/sound_recognition'
labels = open(f'{ASSETS}/yamnet_labels.txt').read().splitlines()
model = Interpreter(f'{ASSETS}/yamnet.tflite')
model.allocate_tensors()
inp = model.get_input_details()[0]['index']
out = model.get_output_details()[0]['index']

for path in sys.argv[1:]:
    with wave.open(path) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), '<i2').astype(np.float32) / 32768
    best = np.zeros(len(labels))
    for start in range(0, len(x) - 15600 + 1, 7800):
        model.set_tensor(inp, x[start:start + 15600])
        model.invoke()
        best = np.maximum(best, model.get_tensor(out)[0])
    top = np.argsort(-best)[:4]
    print(path.split('/')[-1], '->', ' | '.join(f'{labels[i]} {best[i]:.2f}' for i in top))
