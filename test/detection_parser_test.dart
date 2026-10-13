import 'package:flutter_test/flutter_test.dart';
import 'package:sound_recognition/sound_recognition.dart';
import 'package:sound_recognition/src/detection_parser.dart';

void main() {
  Map<Object?, Object?> event({
    Object? classifier = 'yamnet',
    Object? timeMs = 1950,
    Object? labels = const ['Music', 'Bark', 'Theremin'],
    Object? confidences = const [0.52, 0.91, 0.6],
  }) => {
    'event': 'result',
    'classifier': classifier,
    'timeMs': timeMs,
    'labels': labels,
    'confidences': confidences,
  };

  test('maps each label, highest confidence first', () {
    final detections = DetectionParser.parse(event());
    expect(detections.map((d) => d.rawLabel), ['Bark', 'Theremin', 'Music']);
    expect(
      detections.map((d) => d.sound),
      [CanonicalSound.dog, null, CanonicalSound.music],
    );
    expect(detections.first.confidence, 0.91);
    expect(detections.first.timestamp, const Duration(milliseconds: 1950));
    expect(detections.first.classifier, SoundClassifier.yamnet);
  });

  test("reads Apple's identifiers against Apple's vocabulary", () {
    final detections = DetectionParser.parse(
      event(
        classifier: 'apple_sound_analysis_v1',
        labels: ['door_bell', 'Doorbell'],
        confidences: [0.8, 0.7],
      ),
    );
    expect(detections.map((d) => d.sound), [CanonicalSound.doorbell, null]);
  });

  test('accepts integer confidences from the codec', () {
    final d = DetectionParser.parse(
      event(labels: ['Speech'], confidences: [1]),
    ).single;
    expect(d.confidence, 1.0);
  });

  group('drops the window rather than throwing when', () {
    final cases = <String, Map<Object?, Object?>>{
      'the classifier is unknown': event(classifier: 'yamnet_v2'),
      'the classifier is missing': event(classifier: null),
      'timeMs is not an int': event(timeMs: 1.5),
      'the lists differ in length': event(confidences: [0.5]),
      'labels is not a list': event(labels: 'Bark'),
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      test(key, () => expect(DetectionParser.parse(value), isEmpty));
    }
  });

  test('skips individual entries of the wrong type', () {
    final detections = DetectionParser.parse(
      event(labels: ['Bark', 7, 'Music'], confidences: [0.9, 0.8, 'x']),
    );
    expect(detections.map((d) => d.rawLabel), ['Bark']);
  });

  test('SoundDetection has value equality', () {
    expect(DetectionParser.parse(event()), DetectionParser.parse(event()));
  });
}
