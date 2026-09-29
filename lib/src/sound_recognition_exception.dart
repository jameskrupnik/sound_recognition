import 'package:flutter/services.dart';

/// Why listening could not start or had to stop.
enum SoundRecognitionErrorCode {
  /// The microphone permission is not granted. Call
  /// `SoundRecognition.requestPermission` first.
  permissionDenied('PERMISSION_DENIED'),

  /// The device cannot run the classifier — iOS older than 15, which is when
  /// Apple's built-in classifier arrived.
  unsupported('UNSUPPORTED'),

  /// The audio input could not be started or was lost for good: no input
  /// device, the audio session refused the configuration, or `AudioRecord`
  /// would not initialise.
  audioUnavailable('AUDIO_UNAVAILABLE'),

  /// Android only: the bundled YAMNet model or its label list could not be
  /// loaded. This means the plugin's assets were stripped from the APK.
  modelUnavailable('MODEL_UNAVAILABLE'),

  /// Anything the native side reported that this version does not know.
  unknown('UNKNOWN');

  const SoundRecognitionErrorCode(this.wireName);

  /// The code string the native side sends for this error.
  final String wireName;
}

/// A failure reported by the native classifier, with the platform's message.
///
/// Delivered as an error on the stream `SoundRecognition.start` returned.
/// Every one of them is terminal: the stream closes after it.
class SoundRecognitionException implements Exception {
  /// Creates an exception with [code] and an optional platform [message].
  const SoundRecognitionException(this.code, [this.message]);

  /// Translates whatever the channel raised into this package's codes, so
  /// callers switch on an enum rather than on platform strings.
  factory SoundRecognitionException.from(Object error) {
    if (error is SoundRecognitionException) return error;
    if (error is PlatformException) {
      final code = SoundRecognitionErrorCode.values.firstWhere(
        (c) => c.wireName == error.code,
        orElse: () => SoundRecognitionErrorCode.unknown,
      );
      return SoundRecognitionException(code, error.message);
    }
    return SoundRecognitionException(
      SoundRecognitionErrorCode.unknown,
      error.toString(),
    );
  }

  /// What went wrong, as one of this package's codes.
  final SoundRecognitionErrorCode code;

  /// The platform's own description, for logs. Not for users.
  final String? message;

  @override
  String toString() => 'SoundRecognitionException(${code.name}'
      '${message == null ? '' : ': $message'})';
}
