import 'package:sound_recognition/src/canonical_sound.dart';
import 'package:sound_recognition/src/labels_apple_version1.dart';
import 'package:sound_recognition/src/labels_yamnet.dart';

/// Which label set a detection's raw label comes from.
///
/// The wire name is what the native side sends with every result, so the
/// label set is stated by the code that produced the label rather than
/// inferred in Dart from the platform it happens to be running on.
enum SoundClassifier {
  /// `SNClassifySoundRequest(classifierIdentifier: .version1)` on iOS 15+.
  /// Identifiers are snake_case: `dog_bark`.
  appleVersion1('apple_sound_analysis_v1'),

  /// YAMNet (AudioSet ontology, 521 classes) on Android. Labels are the
  /// AudioSet display names: `Bark`, `Vehicle horn, car horn, honking`.
  yamnet('yamnet');

  const SoundClassifier(this.wireName);

  /// The name the native side uses for this classifier on the channel.
  final String wireName;

  /// The classifier with [wireName], or null for one this version of the
  /// package does not know — a newer native half against an older Dart one.
  static SoundClassifier? fromWireName(String wireName) {
    for (final classifier in values) {
      if (classifier.wireName == wireName) return classifier;
    }
    return null;
  }
}

/// The mapping from each [CanonicalSound] to the raw labels that mean it.
///
/// ### Why this is data and not a function
///
/// Every string below was copied from a label list that is committed beside
/// the package — `tool/labels/apple_sound_classifier_version1.txt`, extracted
/// on a Mac from `SNClassifySoundRequest.knownClassifications`, and
/// `tool/labels/yamnet_class_map.csv`, from the TensorFlow models repo — and
/// `test/sound_labels_test.dart` fails if any of them is not in its list. A
/// typo in a label is otherwise silent: the sound simply never fires, and a
/// scavenger hunt waits forever for a doorbell it cannot hear.
///
/// The same test holds three more properties that the lookup relies on:
/// every canonical sound has labels on **both** platforms, no raw label
/// belongs to two canonical sounds (so [canonicalFor] has one answer), and
/// no label set is empty.
///
/// ### Why several labels per sound
///
/// Both classifiers are multi-label and hierarchical. A barking dog scores on
/// YAMNet's `Dog`, `Bark` *and* `Bow-wow` in the same window, and which of
/// them wins varies by recording. A canonical sound's confidence is the
/// highest of its labels, so listing the parent and its children costs nothing
/// and stops the answer from depending on which one the model preferred.
abstract final class SoundLabels {
  /// The Apple `version1` classifier identifiers each sound matches.
  static const Map<CanonicalSound, Set<String>> apple = appleVersion1Labels;

  /// The YAMNet class names each sound matches.
  static const Map<CanonicalSound, Set<String>> yamnet = yamnetLabels;

  /// The mapping for [classifier].
  static Map<CanonicalSound, Set<String>> forClassifier(
    SoundClassifier classifier,
  ) =>
      switch (classifier) {
        SoundClassifier.appleVersion1 => apple,
        SoundClassifier.yamnet => yamnet,
      };

  /// The raw labels that mean [sound] on [classifier].
  static Set<String> labelsFor(
    CanonicalSound sound,
    SoundClassifier classifier,
  ) =>
      forClassifier(classifier)[sound] ?? const {};

  /// The canonical sound [rawLabel] belongs to, or null if it is outside the
  /// canonical set — most of both lists is.
  static CanonicalSound? canonicalFor(
    String rawLabel,
    SoundClassifier classifier,
  ) =>
      _reverse(classifier)[rawLabel];

  static final Map<SoundClassifier, Map<String, CanonicalSound>> _reverseIndex =
      {};

  // Built on first use and kept: a result arrives about twice a second, and
  // each one looks up every label that cleared the confidence floor.
  static Map<String, CanonicalSound> _reverse(SoundClassifier classifier) =>
      _reverseIndex.putIfAbsent(classifier, () {
        return {
          for (final MapEntry(key: sound, value: labels)
              in forClassifier(classifier).entries)
            for (final label in labels) label: sound,
        };
      });
}
