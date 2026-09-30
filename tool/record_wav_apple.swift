// Runs the plugin's own AudioFileRecorder.swift on macOS: feeds each WAV in
// 8192-frame buffers, the tap's size, and reads the m4a back. Each clip is
// recorded twice — once as its own input format, once told the input is
// 96 kHz stereo, which forces the resampling path — and a recorder that gets
// no audio must leave no file.
//
//   out=$(mktemp -d)
//   xcrun swiftc -parse-as-library -o "$out/rec" \
//     ios/sound_recognition/Sources/sound_recognition/AudioFileRecorder.swift \
//     tool/record_wav_apple.swift
//   "$out/rec" "$out" tool/test_audio/*.wav
//
// For the no-conversion path and a stereo downmix, feed it a 48 kHz copy:
//   afconvert -f WAVE -d LEF32@48000 -c 2 tool/test_audio/speech.wav "$out/s.wav"
//
// Not covered: AVAudioEngine, the tap's thread and the audio session.
import AVFoundation

func record(_ wav: String, claimedInput: AVAudioFormat?, to out: String) {
  let src = try! AVAudioFile(forReading: URL(fileURLWithPath: wav))
  let format = src.processingFormat
  guard let recorder = AudioFileRecorder(path: out, inputFormat: claimedInput ?? format) else {
    print("\(out): recorder not created")
    return
  }
  while src.framePosition < src.length {
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192)!
    try! src.read(into: buffer, frameCount: 8192)
    recorder.write(buffer)
  }
  recorder.finishAndWait()
  let back = try! AVAudioFile(forReading: URL(fileURLWithPath: out))
  let isAAC = back.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC
  let bytes = (try! FileManager.default.attributesOfItem(atPath: out)[.size] as! NSNumber).intValue
  print(String(
    format: "%@: in %.3f s at %.0f Hz x%d, out %.3f s at %.0f Hz x%d, %@, %d bytes",
    (out as NSString).lastPathComponent,
    Double(src.length) / format.sampleRate, format.sampleRate, format.channelCount,
    Double(back.length) / back.fileFormat.sampleRate, back.fileFormat.sampleRate,
    back.fileFormat.channelCount, isAAC ? "AAC" : "NOT AAC", bytes))
}

@main
enum RecordWavApple {
  static func main() {
    let args = CommandLine.arguments
    let dir = args[1]
    for wav in args.dropFirst(2) {
      let name = ((wav as NSString).lastPathComponent as NSString).deletingPathExtension
      record(wav, claimedInput: nil, to: "\(dir)/\(name).m4a")
      record(
        wav, claimedInput: AVAudioFormat(standardFormatWithSampleRate: 96_000, channels: 2),
        to: "\(dir)/\(name)-resampled.m4a")
    }
    let empty = "\(dir)/empty.m4a"
    FileManager.default.createFile(atPath: empty, contents: Data("an old file".utf8))
    AudioFileRecorder(
      path: empty, inputFormat: AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!)!
      .finishAndWait()
    print("no audio leaves a file: \(FileManager.default.fileExists(atPath: empty))")
  }
}
