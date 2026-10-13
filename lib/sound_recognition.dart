/// On-device sound classification for iOS and Android, with one vocabulary.
///
/// No Flutter package did this on both platforms, and the reason is that the
/// two platforms' classifiers do not speak the same language. iOS 15+ has one
/// built in — SoundAnalysis's `SNClassifySoundRequest(.version1)`, about 300
/// labels, no model to ship — and Android has nothing built in, so this
/// package bundles Google's YAMNet (521 AudioSet classes) and runs it with
/// LiteRT. Apple says `dog_bark`; YAMNet says `Bark`.
///
/// [CanonicalSound] is the fix: sixty common sounds, each mapped to the raw
/// labels that mean it on both platforms, with a test that holds every
/// mapped label to the platform's real list. The raw labels are still there on
/// every detection for anything outside the sixty.
///
/// ```dart
/// SoundRecognition.instance
///     .start(sounds: {CanonicalSound.doorbell})
///     .listen((d) => print('${d.sound} at ${d.timestamp}'));
/// ```
///
/// **Nothing leaves the device and no network is used, on either platform.**
/// That is a property of the choices underneath, not an accident: see the
/// README for why this is LiteRT and not MediaPipe Tasks, whose Android
/// library reports usage metrics to Google.
///
/// @docImport 'package:sound_recognition/src/canonical_sound.dart';
library;

export 'src/canonical_sound.dart' show CanonicalSound, SoundCategory;
export 'src/microphone_permission.dart' show MicrophonePermission;
export 'src/sound_detection.dart' show SoundDetection;
export 'src/sound_labels.dart' show SoundClassifier, SoundLabels;
export 'src/sound_listening_state.dart' show SoundListeningState;
export 'src/sound_recognition_base.dart' show SoundRecognition;
export 'src/sound_recognition_exception.dart'
    show SoundRecognitionErrorCode, SoundRecognitionException;
