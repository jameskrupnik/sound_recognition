import 'package:flutter_test/flutter_test.dart';
import 'package:sound_recognition/sound_recognition.dart';

void main() {
  SoundDetection detection({double confidence = 0.91}) => SoundDetection(
    sound: CanonicalSound.dog,
    rawLabel: 'Bark',
    confidence: confidence,
    timestamp: const Duration(milliseconds: 1950),
    classifier: SoundClassifier.yamnet,
  );

  test('detections with the same fields are equal and hash alike', () {
    expect(detection(), detection());
    expect(detection().hashCode, detection().hashCode);
    expect(detection(), isNot(detection(confidence: 0.5)));
  });

  test('toString names the sound, label, score and time', () {
    expect(
      detection().toString(),
      'SoundDetection(dog, "Bark", 0.91, 1950 ms)',
    );
    expect(
      const SoundDetection(
        rawLabel: 'Theremin',
        confidence: 0.6,
        timestamp: Duration.zero,
        classifier: SoundClassifier.yamnet,
      ).toString(),
      'SoundDetection(-, "Theremin", 0.60, 0 ms)',
    );
  });
}
