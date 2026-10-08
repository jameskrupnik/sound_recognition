import 'package:sound_recognition/src/sound_detection.dart';
import 'package:sound_recognition/src/sound_labels.dart';

/// Turns one native `result` event into [SoundDetection]s.
///
/// Kept apart from `SoundRecognition` so that the wire format — the one place
/// the Swift, Kotlin and Dart halves have to agree — is tested on its own,
/// without a channel in the way.
///
/// The event is parallel lists rather than a list of maps because it arrives
/// about twice a second and the codec pays per object:
///
/// ```text
/// {event: result, classifier: yamnet, timeMs: 1950,
///  labels: [Speech, Music], confidences: [0.91, 0.52]}
/// ```
///
/// The native side has already dropped labels under the confidence floor, so
/// everything here is reported.
abstract final class DetectionParser {
  /// The detections in [event], highest confidence first.
  ///
  /// Returns an empty list for a malformed event or an unknown classifier
  /// rather than throwing: one bad window is not worth ending the stream for,
  /// and a newer native half speaking a vocabulary this Dart does not know
  /// cannot be mapped anyway.
  static List<SoundDetection> parse(Map<Object?, Object?> event) {
    final classifier = classifierFromWireName(
      event['classifier'] as String? ?? '',
    );
    final timeMs = event['timeMs'];
    final labels = event['labels'];
    final confidences = event['confidences'];
    if (classifier == null ||
        timeMs is! int ||
        labels is! List<Object?> ||
        confidences is! List<Object?> ||
        labels.length != confidences.length) {
      return const [];
    }

    final timestamp = Duration(milliseconds: timeMs);
    final detections = <SoundDetection>[
      for (var i = 0; i < labels.length; i++)
        if (labels[i] case final String label)
          if (confidences[i] case final num confidence)
            SoundDetection(
              sound: SoundLabels.canonicalFor(label, classifier),
              rawLabel: label,
              confidence: confidence.toDouble(),
              timestamp: timestamp,
              classifier: classifier,
            ),
    ]..sort((a, b) => b.confidence.compareTo(a.confidence));
    return detections;
  }
}
