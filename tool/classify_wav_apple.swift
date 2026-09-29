// Runs Apple's built-in classifier over WAV files on this Mac and prints each
// file's four strongest labels, using the same window the plugin configures
// on iOS (0.975 s, 50% overlap).
//
//   xcrun swift tool/classify_wav_apple.swift tool/test_audio/*.wav
//
// This exercises Apple's *model* through SNAudioFileAnalyzer, not the
// plugin's Swift: the plugin feeds SNAudioStreamAnalyzer from a microphone
// tap, which a script cannot do. What it proves is that the labels the
// mapping relies on come out of the model for the sounds they name.
import SoundAnalysis

final class Collector: NSObject, SNResultsObserving {
  var best: [String: Double] = [:]
  func request(_ request: SNRequest, didProduce result: SNResult) {
    guard let result = result as? SNClassificationResult else { return }
    for c in result.classifications.prefix(10) {
      best[c.identifier] = max(best[c.identifier] ?? 0, c.confidence)
    }
  }
}

for path in CommandLine.arguments.dropFirst() {
  let analyzer = try SNAudioFileAnalyzer(url: URL(fileURLWithPath: path))
  let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
  request.windowDuration = CMTime(value: 975, timescale: 1000)
  request.overlapFactor = 0.5
  let collector = Collector()
  try analyzer.add(request, withObserver: collector)
  analyzer.analyze()
  let top = collector.best.sorted { $0.value > $1.value }.prefix(4)
    .map { "\($0.key) \(String(format: "%.2f", $0.value))" }
  print((path as NSString).lastPathComponent, "->", top.joined(separator: " | "))
}
