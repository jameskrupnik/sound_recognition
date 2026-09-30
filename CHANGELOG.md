# Changelog

## Unreleased

- **Added:** `start(recordTo: '/abs/path.m4a')` also saves what the
  microphone hears, as mono AAC in an `.m4a`, from the same capture the
  classifier reads — the input tap on iOS, the `AudioRecord` loop on
  Android. The file is finalized when listening stops for any reason and at
  the first interruption, and is not left behind if no audio arrived.
  Recording is best effort: if the file or encoder cannot be created,
  classification carries on and the reason is only logged. The path must be
  absolute and end in `.m4a`, or `start()` throws `ArgumentError`. Android
  records at YAMNet's 16 kHz. Both encoders are proven on audio files; the
  recording inside the live microphone pipelines has not been run.
- **Fixed:** listening to a stream that a later `start()` or `stop()` had
  already replaced opened the microphone with the stale settings, took over
  the live stream's native session, and could not be stopped by cancelling
  it. Such a stream now just closes.
- **Fixed (Android):** a permission prompt dismissed with Back reported
  `denied` ("go to Settings") although Android would prompt again. It now
  reports `undetermined`; `denied` means the user denied a prompt and then
  denied it again or chose "don't ask again".
- **Fixed (Android):** a hot restart left the `AudioRecord` running until the
  next `start()`. The plugin now stops it from the engine's pre-restart hook.
  iOS has no equivalent hook; see the README.
- **Fixed (Android):** before Android 10, `startRecording()` fails silently
  while another app holds the mic, and the listener reported `listening`
  over a recorder that never delivered audio. It now reports `interrupted`
  and retries every second, and a failed read backs off rather than
  reopening the recorder in a tight loop.

## 0.1.0

Initial cut. On-device sound classification from the microphone on iOS and
Android, with one shared vocabulary.

- **iOS 15+:** Apple's built-in `SNClassifySoundRequest(.version1)`, fed from
  an `AVAudioEngine` input tap through `SNAudioStreamAnalyzer`. No model to
  ship. CocoaPods and Swift Package Manager, from one source tree.
- **Android 7+ (API 24):** YAMNet, bundled (4.1 MB), run on LiteRT 1.4.2's
  `Interpreter`. **Not MediaPipe Tasks**, which was the plan, because
  MediaPipe reports usage metrics to Google and this package promises no
  network at runtime. See the README.
- `CanonicalSound`: 60 common, kid-relevant sounds, each mapped to Apple
  identifiers and YAMNet class names as data. A test checks every mapped
  label against the platform's real list, committed under `tool/labels/`.
- Raw labels on every detection, a `rawLabels` filter, and `knownLabels()`
  for everything outside the sixty.
- Microphone permission reduced to `granted` / `undetermined` / `denied` —
  the one question an app has to answer, which is whether asking will show a
  prompt.
- Interruptions surface as `SoundListeningState.interrupted` and resume on
  their own: iOS audio-session interruptions, route and engine configuration
  changes, media-services resets; Android background/foreground and another
  app silencing the mic (API 29+).
- 0.975 s windows on both platforms, so a threshold and a latency mean
  roughly the same thing on each.
- An example app with a live detection list and a one-sound "hunt".

**The classifiers are proven on audio files. The live microphone pipelines on
both platforms compile and build but have not been run against a real
microphone.** See "What is proven" in the README.
