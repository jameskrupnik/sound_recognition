// Prints every label Apple's built-in sound classifier can produce, one per
// line, sorted. This is how labels/apple_sound_classifier_version1.txt was made:
//
//   xcrun swift tool/print_apple_labels.swift > tool/labels/apple_sound_classifier_version1.txt
//
// It runs on the Mac because SoundAnalysis ships on macOS 12+ with the same
// `.version1` classifier as iOS 15+. Re-run it when a new OS ships: Apple has
// not changed the list since 2021, but `.version1` is a promise about the
// model, not about the future.
import SoundAnalysis

let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
for label in request.knownClassifications.sorted() { print(label) }
