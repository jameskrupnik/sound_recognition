# sound_recognition

On-device sound classification for Flutter on iOS and Android, with **one
vocabulary on both**. Apple's built-in SoundAnalysis classifier on iOS, a
bundled YAMNet model on Android, and no network at runtime on either.

```dart
SoundRecognition.instance
    .start(sounds: {CanonicalSound.doorbell, CanonicalSound.telephone})
    .listen((d) => print('${d.sound!.displayName} at ${d.timestamp}'));
```

## Why this exists

No Flutter package classified sound on both platforms. `apple_sound_analysis`
is iOS-only, and `tflite_audio` has not been maintained in years. The native
pieces exist on both sides, but they do not agree on what anything is called:

| | iOS 15+ | Android |
|---|---|---|
| Classifier | `SNClassifySoundRequest(classifierIdentifier: .version1)` | YAMNet (AudioSet), bundled |
| Labels | 303 | 521 |
| A barking dog | `dog_bark` | `Bark`, `Dog`, `Bow-wow` |
| Model to ship | none, it is in the OS | 4.1 MB |

A game that says "find something that rings" should not have to know either
list. That is the whole point of `CanonicalSound`: sixty common sounds, each
mapped to the raw labels that mean it on each platform.

## Tuning

Two things are worth knowing before you tune a game:

- **Apple's model hallucinates over speech in short windows.** Speech can
  score `mosquito_buzz` above 0.9 in an occasional window. That would count
  as `insectBuzz` at any sensible threshold. If one false "found it" matters,
  require two detections within a couple of seconds.
- **The window is a trade, and 0.975 s was chosen on purpose.** Apple's
  default is 3 s. At 3 s a phone ring stopped being `telephone` at all
  (top label `synthesizer` 0.52) and a whistle dropped to 0.53, because a
  short sound is diluted by what surrounds it. At 3 s the `mosquito_buzz`
  false positive also dropped to 0.30. Knocks, dings and claps are short, and
  a hunt is looking for them, so the short window won. It also matches
  YAMNet's fixed window, so latency and thresholds mean roughly the same
  thing on both platforms.

## Install

```yaml
dependencies:
  sound_recognition: ^0.1.0
```

Flutter 3.44 or later (Dart 3.12). The Android build relies on the Kotlin
support that Flutter 3.44's Gradle plugin applies. Android `minSdk` 24
(Android 7). iOS: the plugin installs on iOS 13, and
`isSupported()` returns false before iOS 15, when Apple's classifier arrived.
That lets an app with a 13 floor add it and hide the feature, instead of
being refused the dependency.

### iOS: `NSMicrophoneUsageDescription` (required)

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Listens for sounds so you can find them. Audio stays on this device.</string>
```

If you use [recording](#recording), say so in the string — "Listens to and
records your practice so it can be played back. Recordings stay on this
device." — because App Review reads it against what the app does.

Without it, iOS **terminates the app** at `requestPermission()`.

CocoaPods and Swift Package Manager are both supported, from the same source
tree (`ios/sound_recognition/Sources`). The example builds either way.

### Android: `RECORD_AUDIO`

Declared in the plugin's manifest and merged into yours, so there is nothing
to add. Say so in the Play Data safety form: audio is *accessed*, and because
it is processed only in memory and never stored or sent, Google's definitions
do not count that as *collected*. With [recording](#recording) on, audio *is*
stored, on the device; data that never leaves the device is still not
*collected* by Google's definitions, but check the current form wording
yourself.

The model and the LiteRT runtime together cost about **8.6 MB installed on an
arm64 device** (4.1 MB model + 4.5 MB `libtensorflowlite_jni.so`, both stored
uncompressed), or about 5 MB of download. An app bundle delivers one ABI; a
universal APK from Flutter carries three (another 8.9 MB).

## Use

```dart
final recognition = SoundRecognition.instance;
if (!await recognition.isSupported()) return hideSoundMode();

switch (await recognition.requestPermission()) {
  case MicrophonePermission.granted:
    break;
  case MicrophonePermission.denied:
    return showGoToSettings(); // asking again will not show a prompt
  case MicrophonePermission.undetermined:
    return; // the user dismissed it; ask again later
}

final subscription = recognition
    .start(
      minConfidence: 0.5,           // floor under which labels are dropped
      overlap: 0.5,                 // ~2 results a second
      sounds: {CanonicalSound.bell}, // canonical filter…
      rawLabels: {'Wind chime'},     // …plus any raw labels, as a union
    )
    .listen(
      (d) => found(d.sound, d.rawLabel, d.confidence, d.timestamp),
      onError: (Object e) => handle(e as SoundRecognitionException),
    );

// Listening stops when the subscription is cancelled, on stop(), or when
// start() is called again — there is one microphone, so the newer call wins.
// A stream that was replaced or stopped before anyone listened to it is
// already closed: listening to it later does not open the microphone.
await subscription.cancel();
```

### Recording

Pass `recordTo:` and the microphone audio is also saved, so it can be played
back later:

```dart
final path = '${(await getApplicationSupportDirectory()).path}/session-42.m4a';
final subscription = recognition
    .start(sounds: {CanonicalSound.piano}, recordTo: path)
    .listen(onDetection);
// …
await subscription.cancel(); // the file is finalized here
if (File(path).existsSync()) savePracticeRecording(path);
```

- **One pipeline.** The file is written from the same capture the classifier
  reads — the `AVAudioEngine` input tap on iOS, the `AudioRecord` loop on
  Android — never from a second recorder. Encoding runs on a thread of its
  own, so it does not hold up classification.
- **Format:** `.m4a` (MPEG-4), AAC-LC, mono, about 64 kbps — roughly
  0.5 MB a minute, 29 MB an hour. **Android records at 16 kHz**, because that
  is what YAMNet listens to: fine for hearing whether and what someone
  played, not a hi-fi recording. iOS records at the mic's own rate (usually
  48 kHz; 44.1 kHz if the input is outside 22.05–48 kHz).
- **The path** must be absolute and end in `.m4a`, or `start()` throws an
  `ArgumentError`. The directory must exist. A file already there is replaced.
- **When it ends.** The file is finalized when listening stops for any
  reason — `stop()`, cancelling the subscription, another `start()`, an
  error — and at the **first `SoundListeningState.interrupted`**: a call,
  Siri, another app taking the mic, and on Android the app going to the
  background. Classification resumes after an interruption; the recording
  does not, because an m4a cannot be appended to, and finalizing then means
  a process killed in the background still leaves a playable file. To keep
  recording, watch `stateChanges` and call `start()` again with a new path.
  A route change on iOS (headphones in or out) is not an interruption, and
  the recording carries on.
- **Finalized when the future completes.** On iOS, `stop()` and
  `subscription.cancel()` complete after the file is closed. On Android the
  plugin waits up to a second for it, which is normally plenty.
- **Diagnosing a missed sound.** The file is exactly what the classifier
  heard, so recording is also the way to tell a sound the microphone never
  picked up from one the classifier missed.
- **No audio, no file.** If nothing was captured (say the stream was
  interrupted before audio arrived), no file is left, so a file that exists
  is a playable one.
- **Best effort.** If the file cannot be created or the encoder fails,
  classification carries on without it and the stream sees nothing; the
  reason is logged natively (`sound_recognition` in logcat, the device
  console on iOS). The `SoundDetection` stream is deliberately unchanged, so
  check that the file exists before offering playback.

**The file is yours.** It exists only on the device — the plugin never sends
it anywhere — and the app is responsible for it: where it lives, showing it,
and **deleting it**. The plugin never deletes a finished recording. Mind
backups: iOS backs up Documents and Application Support to iCloud, and
Android Auto Backup includes app files, unless you exclude them. Tell the
user plainly that audio is being saved (both platforms show their own mic
indicator, which says *listening*, not *saving*), and remember that a
recording of a room records whoever is in it.

### Detections are per label, not merged

Both classifiers are multi-label, so one window can yield `Dog`, `Bark` and
`Bow-wow` together, and each arrives as its own `SoundDetection` with
`sound: CanonicalSound.dog`. Merging them would hide the raw labels that an app
going beyond the canonical set asked for. A hunt that only cares whether the
dog was heard takes the first detection.

**Timestamps restart with every `start()`.** `SoundDetection.timestamp` is
when the window began, measured from when that `start()`'s stream began
listening, so a `start()` after `stop()` counts from zero again. Within one
stream it keeps rising across an interruption and includes the time spent
interrupted. Both platforms follow this rule.

**Confidence is not comparable across platforms.** Both models score each
label independently (sigmoid), so the scores in a window do not sum to one,
and the same sound scores differently on each model. Tune per platform if a
threshold matters.

### Interruptions

`SoundRecognition.instance.state` and `stateChanges` report `listening`,
`interrupted` and `stopped`. Interruptions resume on their own:

- **iOS:** audio-session interruptions (calls, Siri, alarms) resume on
  `.ended` whether or not the system says `.shouldResume`, and again when the
  app becomes active, because `.ended` is not guaranteed. Route changes
  (headphones in or out) and engine configuration changes rebuild the tap
  against the new input format. A media-services reset rebuilds everything.
- **Android:** capture pauses when the activity stops and resumes when it
  starts. Android 9+ silences background capture anyway, and releasing the
  recorder frees the mic for whatever the user switched to. On Android 10+,
  when another app takes the microphone, Android *silences* this one rather
  than stopping it. The plugin detects that (`isClientSilenced`, API 29+) and
  reports `interrupted` instead of classifying silence. Before Android 10 the
  other app wins outright and `startRecording()` fails; that is also reported
  as `interrupted`, and retried every second.

**Hot restart** does not cancel channel streams. On Android the plugin stops
the microphone from the engine's pre-restart hook. iOS has no such hook for
plugins, so in a debug session the mic stays on after a hot restart until the
app next calls `start()`, which replaces the old session.

Fatal errors arrive as a `SoundRecognitionException` on the stream, which then
closes: `permissionDenied`, `unsupported`, `audioUnavailable`,
`modelUnavailable` (Android assets stripped), `unknown`.

### iOS audio session: the trade-off

Listening sets the session to `.playAndRecord` with `.mixWithOthers`,
`.defaultToSpeaker` and `.allowBluetoothA2DP`, and puts the previous category
back on stop:

- `.record` would silence the game's own audio, so it was out.
- `.mixWithOthers` keeps the game's audio and other apps' audio playing.
- `.defaultToSpeaker` stops `.playAndRecord` from moving output to the
  earpiece.
- `.allowBluetoothA2DP` keeps Bluetooth headphones in high quality. `.allowBluetooth`
  (HFP) was left out on purpose, because it would drop headphones to call
  quality in order to use their mic.

The costs:

- The classifier hears the game. A game whose sound effect is a dog bark will
  find a dog, so duck or pause effects that overlap the hunt's targets.
- Some routes apply voice processing and play slightly quieter.
- If your audio plugin sets its own category after `start()` (a plain
  `.playback`), recording stops. Configure it for `.playAndRecord` too, or
  start listening after it.

The session is deliberately **not deactivated** on stop, because that would
cut off the game's audio mid-sound.

## The vocabulary

Sixty sounds in five groups (`SoundCategory`): animals (10), people (15),
home (20), music (7), outdoors (8). The mapping is data, in
`lib/src/labels_apple_version1.dart` and `lib/src/labels_yamnet.dart`.
`test/sound_labels_test.dart` holds it to four rules:

1. Every mapped label exists in the platform's real list:
   `tool/labels/apple_sound_classifier_version1.txt`, extracted on a Mac by
   `tool/print_apple_labels.swift`, and `tool/labels/yamnet_class_map.csv`
   from `tensorflow/models`. A typo is otherwise silent: the sound just never
   fires.
2. Every canonical sound maps on **both** platforms.
3. No raw label belongs to two canonical sounds.
4. The Android label asset is YAMNet's class map, in model output order. It
   was extracted from the model file's own metadata, so this also proves that
   the model and the map agree.

**Left out on purpose:**

- **One-platform sounds.** A hunt item that can only be found on an iPhone is
  a bug report. These stay reachable through raw labels.
  - Apple only: `nose_blowing`, `rope_skipping`.
  - YAMNet only: `Fart`, `Ice cream truck, ice cream van`, `Children
    playing`, `Television`, `Stomach rumble`, `Lullaby`, `Buzzer`, `Car alarm`.
- **Smoke and fire alarms.** Both platforms have them, but a child should not
  be sent to set one off. A test keeps them out.

## Privacy, and why Android is LiteRT rather than MediaPipe

The brief was MediaPipe Tasks' `AudioClassifier` (`com.google.mediapipe:tasks-audio`,
1.0.0 at the time of writing), the documented way to run YAMNet on Android. It
was dropped after reading its privacy notice:

> MediaPipe Tasks APIs send metrics about the performance and utilization of
> the APIs in your app to Google.

`tasks-core` pulls in `transport-backend-cct` to do exactly that. For a
children's game that promises nothing leaves the phone, a classifier that
phones home breaks the promise. It also has to be disclosed in the Data safety
form.

The same model on **LiteRT 1.4.2** (`com.google.ai.edge.litert:litert`,
TensorFlow Lite renamed) depends only on its own `litert-api` and has no telemetry. Its
native libraries are 16 KB page-aligned, which Play requires. What MediaPipe
added for this model was thin: YAMNet's input is raw 16 kHz samples, with the
spectrogram computed inside the graph, so the plugin only has to window the
audio. LiteRT 2.x has the same `Interpreter`, but it adds a GPU accelerator,
Guava, coroutines and a model-delivery library that this package does not use.

The example's **release APK declares no `INTERNET` permission at all**. The
only permission it holds is `RECORD_AUDIO`.

### The model: bundled, not downloaded

`yamnet.tflite` (float32, 4,126,810 bytes, sha256 `4d8b4a53…4c584faf`) comes
from Google's MediaPipe model bucket,
`storage.googleapis.com/mediapipe-models/audio_classifier/yamnet/float32/1/`,
and ships in the plugin's Android assets. The alternative, downloading it on
first use, was rejected because:

- **No network at runtime** is a requirement, not a preference.
- A download needs somewhere to fail. A kid on a plane gets a broken game,
  and every consumer would need retry UI.
- 4.1 MB is small next to a Flutter engine (11.6 MB on arm64).

YAMNet is Apache 2.0 (TensorFlow models); the AudioSet class names are CC BY
4.0.

## Tooling

```console
$ xcrun swift tool/print_apple_labels.swift > tool/labels/apple_sound_classifier_version1.txt
$ xcrun swift tool/classify_wav_apple.swift tool/test_audio/*.wav
$ xcrun swift tool/classify_wav_apple_stream.swift tool/test_audio/*.wav
$ xcrun swiftc -parse-as-library -o /tmp/rec ios/sound_recognition/Sources/sound_recognition/AudioFileRecorder.swift tool/record_wav_apple.swift && /tmp/rec /tmp tool/test_audio/*.wav
$ python3 tool/classify_wav_yamnet.py tool/test_audio/*.wav     # pip install ai-edge-litert numpy
$ cd example/android && ./gradlew :sound_recognition:testDebugUnitTest          # JVM, no device
$ cd example/android && ./gradlew :sound_recognition:connectedDebugAndroidTest
```

## Licence

MIT. See [LICENSE](LICENSE).

The bundled YAMNet model and its class names are Google's, under the Apache
License 2.0, not MIT. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) lists
exactly what is redistributed. The Apache licence text ships beside the model
inside every app, and an app should also list it on its own licences screen
(Flutter's `LicenseRegistry`).
