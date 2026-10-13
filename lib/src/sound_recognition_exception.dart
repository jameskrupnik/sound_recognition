/// @docImport 'package:sound_recognition/src/sound_recognition_base.dart';
library;

import 'package:flutter/services.dart';

/// Why listening could not start or had to stop.
enum SoundRecognitionErrorCode {
  /// The microphone permission is not granted.
  ///
  /// Call [SoundRecognition.requestPermission] first.
  permissionDenied,

  /// The device cannot run the classifier — iOS older than 15, which is when
  /// Apple's built-in classifier arrived.
  unsupported,

  /// The audio input could not be started or was lost for good: no input
  /// device, the audio session refused the configuration, or `AudioRecord`
  /// would not initialise.
  audioUnavailable,

  /// Android only: the bundled YAMNet model or its label list could not be
  /// loaded.
  ///
  /// This means the plugin's assets were stripped from the APK.
  modelUnavailable,

  /// Any other failure, with the platform's own description as the message.
  ///
  /// iOS sends this when Apple's classifier fails mid-stream, because
  /// SoundAnalysis does not say why in any way worth a code of its own. It
  /// is also what an error code this version does not know becomes.
  unknown,
}

/// A failure reported by the native classifier, with the platform's message.
///
/// Delivered as an error on the stream [SoundRecognition.start] returned.
/// Every one of them is terminal: the stream closes after it.
class SoundRecognitionException implements Exception {
  /// Creates an exception with [code] and an optional platform [message].
  const SoundRecognitionException(this.code, [this.message]);

  /// What went wrong, as one of this package's codes.
  final SoundRecognitionErrorCode code;

  /// The platform's own description, for logs.
  ///
  /// Not for users.
  final String? message;

  @override
  String toString() =>
      'SoundRecognitionException(${code.name}'
      '${message == null ? '' : ': $message'})';
}

/// Translates whatever the channel raised into this package's codes, so
/// callers switch on an enum rather than on platform strings.
///
/// Not exported: the native code strings are the channel protocol, not API.
SoundRecognitionException toSoundRecognitionException(Object error) {
  if (error is SoundRecognitionException) return error;
  if (error is PlatformException) {
    final code = switch (error.code) {
      'PERMISSION_DENIED' => SoundRecognitionErrorCode.permissionDenied,
      'UNSUPPORTED' => SoundRecognitionErrorCode.unsupported,
      'AUDIO_UNAVAILABLE' => SoundRecognitionErrorCode.audioUnavailable,
      'MODEL_UNAVAILABLE' => SoundRecognitionErrorCode.modelUnavailable,
      _ => SoundRecognitionErrorCode.unknown,
    };
    return SoundRecognitionException(code, error.message);
  }
  return SoundRecognitionException(
    SoundRecognitionErrorCode.unknown,
    error.toString(),
  );
}
