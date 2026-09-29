// Feeds WAV files to Apple's classifier through SNAudioStreamAnalyzer the way
// the plugin's SoundListener feeds it from the microphone tap: 8192-frame
// buffers, frame positions counted from zero, a 0.975 s window, 50% overlap,
// labels under the floor dropped. Prints each result the plugin would send.
//
//   xcrun swift tool/classify_wav_apple_stream.swift tool/test_audio/*.wav
//
// Not covered: AVAudioEngine, the audio session and interruptions, none of
// which a script can drive.
import AVFoundation
import SoundAnalysis

final class Printer: NSObject, SNResultsObserving {
  var lines: [String] = []
  func request(_ request: SNRequest, didProduce result: SNResult) {
    guard let r = result as? SNClassificationResult else { return }
    let kept = r.classifications.prefix { $0.confidence >= 0.5 }
    guard !kept.isEmpty else { return }
    let ms = Int(r.timeRange.start.seconds * 1000)
    lines.append("  \(ms) ms: " + kept.map { "\($0.identifier) \(String(format: "%.2f", $0.confidence))" }.joined(separator: ", "))
  }
}

for path in CommandLine.arguments.dropFirst() {
  let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
  let format = file.processingFormat
  let analyzer = SNAudioStreamAnalyzer(format: format)
  let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
  request.windowDuration = CMTime(value: 975, timescale: 1000)
  request.overlapFactor = 0.5
  let printer = Printer()
  try analyzer.add(request, withObserver: printer)
  var position: AVAudioFramePosition = 0
  while file.framePosition < file.length {
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192)!
    try file.read(into: buffer)
    analyzer.analyze(buffer, atAudioFramePosition: position)
    position += AVAudioFramePosition(buffer.frameLength)
  }
  analyzer.completeAnalysis()
  print((path as NSString).lastPathComponent)
  printer.lines.forEach { print($0) }
}
