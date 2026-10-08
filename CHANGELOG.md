# Changelog

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

Changes made before the first publish, found while integrating it into an app:

- **Added:** `start(recordTo: '/abs/path.m4a')` also saves what the
  microphone hears, as mono AAC in an `.m4a`, from the same capture the
  classifier reads — the input tap on iOS, the `AudioRecord` loop on
  Android. The file is finalized when listening stops for any reason and at
  the first interruption, and is not left behind if no audio arrived.
  Recording is best effort: if the file or encoder cannot be created,
  classification carries on and the reason is only logged. The path must be
  absolute and end in `.m4a`, or `start()` throws `ArgumentError`. Android
  records at YAMNet's 16 kHz.
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
- **Changed:** the channel's wire strings are no longer public API.
  `SoundClassifier.wireName`, `SoundClassifier.fromWireName`,
  `SoundRecognitionErrorCode.wireName` and the
  `SoundRecognitionException.from` factory are gone; they described the
  protocol between the Dart and native halves, which no app should depend
  on. Switch on the enums instead.
- **Documented:** `SoundDetection.timestamp` counts from zero for every
  `start()`, including one after `stop()`, and within one stream keeps rising
  across interruptions. Both platforms already did this; it is now stated.
- **Fixed (iOS):** after an interruption or route change, the last results
  of the previous engine run arrived once the new run had started and were
  stamped with the new run's offset, so their timestamps jumped and could
  arrive out of order. Each run's results now carry their own run's offset.
- **Fixed (Android):** if the activity stopped and started again before the
  capture thread noticed (a quick background and return), the capture loop
  carried on reading the `AudioRecord` the pause had stopped: no audio, no
  results, and the state stuck at `interrupted` until `stop()`. A pause now
  ends the capture segment for good, and a fresh recorder is opened on
  resume. A pause landing as capture started could also leave the state
  reading `listening` while paused; the two are now ordered.
- **Fixed (Android):** a mic-silencing change already queued when a listener
  was stopped could be delivered into the next `start()`'s stream as a stale
  `interrupted`. Each listener now speaks only to its own stream, and only
  while it is current.
- **Fixed (Android):** after Android stopped silencing the mic, the first
  windows mixed the silenced stretch's zeros with real audio, reporting
  `Silence` and diluting what was really there. Silenced audio is now dropped
  from the windows, while timestamps still count it.
- **Fixed (Android):** at `overlap` 0.8 and 0.9 the hop was one sample short
  (floating-point truncation), so every timestamp drifted by a sample a
  window.
- **Fixed (Android):** a pause while the model was still loading did not stop
  the recording from starting afterwards; the recording now ends at the first
  interruption however early it comes.
- **Example:** the Hunt tab no longer sticks at "Listening…" with its button
  disabled when its stream ends with an error or is replaced; the Live tab
  clears its list on each Listen (timestamps restart) and has a **Save audio**
  switch that records the session through `recordTo` and reports the file.
