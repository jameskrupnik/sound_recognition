import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sound_recognition/sound_recognition.dart';
import 'package:sound_recognition/src/sound_labels.dart';

/// The test that keeps the mapping honest.
///
/// A mislabelled entry in [SoundLabels] is silent at runtime — the sound just
/// never fires — so every string in it is checked here against the platform's
/// real label list, committed under `tool/labels/`:
///
///  - `apple_sound_classifier_version1.txt`, printed on macOS 26.5 by
///    `tool/print_apple_labels.swift` from
///    `SNClassifySoundRequest(classifierIdentifier: .version1)
///    .knownClassifications`.
///  - `yamnet_class_map.csv`, from `tensorflow/models`
///    `research/audioset/yamnet/`.
void main() {
  final apple = File(
    'tool/labels/apple_sound_classifier_version1.txt',
  ).readAsLinesSync().where((l) => l.isNotEmpty).toList();
  final yamnet = _yamnetDisplayNames(
    File('tool/labels/yamnet_class_map.csv').readAsStringSync(),
  );

  group('reference label lists', () {
    test('are the sizes the platforms document', () {
      // Apple says "more than 300"; YAMNet is the 521-class AudioSet subset.
      expect(apple, hasLength(303));
      expect(yamnet, hasLength(521));
    });

    test("the Android asset is YAMNet's class map, in model output order", () {
      // The Kotlin side maps output index i to line i of this file. It was
      // extracted from the model's own embedded metadata, so this also proves
      // the model and the committed class map agree.
      final asset = File(
        'android/src/main/assets/sound_recognition/yamnet_labels.txt',
      ).readAsLinesSync().where((l) => l.isNotEmpty).toList();
      expect(asset, yamnet);
    });
  });

  for (final (classifier, known) in [
    (SoundClassifier.appleVersion1, apple.toSet()),
    (SoundClassifier.yamnet, yamnet.toSet()),
  ]) {
    group('${classifier.name} mapping', () {
      final mapping = SoundLabels.forClassifier(classifier);

      test('covers every canonical sound, and nothing else', () {
        expect(mapping.keys.toSet(), CanonicalSound.values.toSet());
      });

      test('has at least one label for every canonical sound', () {
        for (final sound in CanonicalSound.values) {
          expect(mapping[sound], isNotEmpty, reason: sound.name);
        }
      });

      test('uses only labels that exist in the platform list', () {
        final unknown = {
          for (final MapEntry(:key, :value) in mapping.entries)
            for (final label in value)
              if (!known.contains(label)) '${key.name}: "$label"',
        };
        expect(unknown, isEmpty);
      });

      test('never gives one raw label to two canonical sounds', () {
        final owners = <String, List<String>>{};
        for (final MapEntry(:key, :value) in mapping.entries) {
          for (final label in value) {
            (owners[label] ??= []).add(key.name);
          }
        }
        owners.removeWhere((_, sounds) => sounds.length == 1);
        expect(owners, isEmpty);
      });

      test('canonicalFor inverts labelsFor', () {
        for (final sound in CanonicalSound.values) {
          for (final label in SoundLabels.labelsFor(sound, classifier)) {
            expect(SoundLabels.canonicalFor(label, classifier), sound);
          }
        }
      });
    });
  }

  group('canonicalFor', () {
    test('keeps the vocabularies apart', () {
      expect(
        SoundLabels.canonicalFor('dog_bark', SoundClassifier.appleVersion1),
        CanonicalSound.dog,
      );
      expect(
        SoundLabels.canonicalFor('Bark', SoundClassifier.yamnet),
        CanonicalSound.dog,
      );
      expect(
        SoundLabels.canonicalFor('Bark', SoundClassifier.appleVersion1),
        isNull,
      );
    });

    test('returns null for a label outside the canonical set', () {
      expect(
        SoundLabels.canonicalFor('theremin', SoundClassifier.appleVersion1),
        isNull,
      );
      expect(
        SoundLabels.canonicalFor('Silence', SoundClassifier.yamnet),
        isNull,
      );
    });
  });

  test('no canonical sound is one a child should be sent to set off', () {
    const alarms = {
      'smoke_detector',
      'Smoke detector, smoke alarm',
      'Fire alarm',
    };
    for (final classifier in SoundClassifier.values) {
      for (final labels in SoundLabels.forClassifier(classifier).values) {
        expect(labels.intersection(alarms), isEmpty);
      }
    }
  });

  test('wire names map to classifiers', () {
    expect(
      classifierFromWireName('apple_sound_analysis_v1'),
      SoundClassifier.appleVersion1,
    );
    expect(classifierFromWireName('yamnet'), SoundClassifier.yamnet);
    expect(classifierFromWireName('something_newer'), isNull);
  });
}

/// The `display_name` column of YAMNet's class map, in index order.
///
/// A three-column CSV where only the last column is ever quoted (it holds
/// names like `"Vehicle horn, car horn, honking"`), so this splits the first
/// two commas off and unquotes the rest rather than pulling in a CSV package.
List<String> _yamnetDisplayNames(String csv) {
  final lines = csv.split('\n').skip(1).where((l) => l.trim().isNotEmpty);
  return [
    for (final line in lines)
      () {
        final rest = line
            .substring(line.indexOf(',', line.indexOf(',') + 1) + 1)
            .trimRight();
        return rest.startsWith('"')
            ? rest.substring(1, rest.length - 1).replaceAll('""', '"')
            : rest;
      }(),
  ];
}
