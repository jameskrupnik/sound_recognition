/// @docImport 'package:sound_recognition/src/sound_recognition_base.dart';
library;

/// Whether the microphone is currently being classified.
enum SoundListeningState {
  /// Not listening: [SoundRecognition.start] has not been called, or the
  /// stream it returned was cancelled or stopped.
  stopped,

  /// Audio is being captured and classified.
  listening,

  /// Listening was asked for but the platform has taken the microphone away
  /// for now.
  ///
  /// That is a phone call or Siri on iOS, the app going to the background,
  /// or another app claiming the microphone on Android. No detections arrive
  /// in this state. Listening resumes on its own when the platform gives the
  /// microphone back, and the state returns to [listening].
  interrupted,
}
