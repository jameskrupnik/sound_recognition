# Third-party notices

`sound_recognition` itself is MIT-licensed (see [LICENSE](LICENSE)). It
redistributes the following files, which are not MIT and keep their own
licence.

## YAMNet (Google LLC), Apache License 2.0

- `android/src/main/assets/sound_recognition/yamnet.tflite`: the YAMNet
  audio classification model, float32 version 1, downloaded unmodified from
  `https://storage.googleapis.com/mediapipe-models/audio_classifier/yamnet/float32/1/yamnet.tflite`.
- `android/src/main/assets/sound_recognition/yamnet_labels.txt` and
  `tool/labels/yamnet_class_map.csv`: YAMNet's class names, from
  `https://github.com/tensorflow/models/tree/master/research/audioset/yamnet`.
  The `.txt` holds the same names in model output order.

Copyright Google LLC. Licensed under the Apache License, Version 2.0. The
full licence text is in `android/src/main/assets/sound_recognition/LICENSE-yamnet.txt`,
which ships inside every app that uses this plugin, beside the model.

YAMNet's class names come from Google's AudioSet ontology,
`https://research.google.com/audioset/`, published under CC BY 4.0
(`https://creativecommons.org/licenses/by/4.0/`). That attribution is also
at the top of `LICENSE-yamnet.txt`, so it ships with the names.

## Apple SoundAnalysis labels

`tool/labels/apple_sound_classifier_version1.txt` lists the identifiers that
Apple's built-in classifier reports, read at runtime from
`SNClassifySoundRequest.knownClassifications` by `tool/print_apple_labels.swift`.
It is used only by tests that check the mapping, and it is not shipped in apps.
No Apple model is redistributed: on iOS the classifier is part of the
operating system.
