import 'package:flutter/foundation.dart';
import 'package:sound_recognition/src/canonical_sound.dart';
import 'package:sound_recognition/src/sound_labels.dart';
import 'package:sound_recognition/src/sound_listening_state.dart';

/// One label that cleared the confidence floor in one analysis window.
///
/// Both classifiers are multi-label, so a single window can produce several
/// detections — and a barking dog routinely produces three for the *same*
/// canonical sound (`Dog`, `Bark`, `Bow-wow` on YAMNet). They are reported
/// individually rather than merged, because merging would hide exactly the
/// raw labels an app reaching beyond the canonical set asked for. A game that
/// only cares whether the dog was heard checks [sound] and takes the first.
@immutable
class SoundDetection {
  /// Creates a detection.
  ///
  /// Normally built by the plugin, not by apps.
  const SoundDetection({
    required this.rawLabel,
    required this.confidence,
    required this.timestamp,
    required this.classifier,
    this.sound,
  });

  /// The canonical sound [rawLabel] belongs to, or null for a label outside
  /// the canonical set — `theremin`, `Heavy metal`, `Silence`.
  final CanonicalSound? sound;

  /// The label exactly as the platform classifier named it.
  ///
  /// Only meaningful against [classifier]'s vocabulary: `dog_bark` on iOS, `Bark` on Android.
  final String rawLabel;

  /// The classifier's score for [rawLabel], 0 to 1.
  ///
  /// **Not a calibrated probability, and not comparable across platforms.**
  /// Both models score each label independently (sigmoid, not softmax), so
  /// the scores in a window do not sum to one, and the same sound scores
  /// differently on Apple's model and on YAMNet. Tune a threshold per
  /// platform if it matters.
  final double confidence;

  /// When the analysed window *began*, measured from when the stream that
  /// delivered it started listening.
  ///
  /// A window is about one second long, so the sound itself was
  /// somewhere in `[timestamp, timestamp + 975 ms]`.
  ///
  /// The clock belongs to one `start()`: every call to `start()` counts from
  /// zero again, including one made after `stop()`. Within one stream it keeps
  /// rising across a [SoundListeningState.interrupted] spell, which it
  /// includes, so times stay in order and a gap shows where the interruption
  /// was. Both platforms follow this rule.
  final Duration timestamp;

  /// Which platform classifier produced [rawLabel].
  final SoundClassifier classifier;

  @override
  bool operator ==(Object other) =>
      other is SoundDetection &&
      other.sound == sound &&
      other.rawLabel == rawLabel &&
      other.confidence == confidence &&
      other.timestamp == timestamp &&
      other.classifier == classifier;

  @override
  int get hashCode =>
      Object.hash(sound, rawLabel, confidence, timestamp, classifier);

  @override
  String toString() =>
      'SoundDetection(${sound?.name ?? '-'}, "$rawLabel", '
      '${confidence.toStringAsFixed(2)}, ${timestamp.inMilliseconds} ms)';
}
