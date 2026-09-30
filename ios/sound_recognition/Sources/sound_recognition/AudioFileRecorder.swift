import AVFoundation

/// The microphone's buffers in, a mono AAC `.m4a` out.
///
/// Fed from the input tap the classifier already runs, never from a second
/// recorder — there is one microphone. The tap runs on a real-time audio
/// thread, so [write] only hands the buffer to a serial queue of its own;
/// conversion and encoding happen there, apart from the analysis queue, so
/// the classifier is never kept waiting on the encoder.
///
/// Best effort by design: every failure is logged and ends the recording, and
/// none reaches the caller, because a broken recording must not stop the
/// listening it rides on. The file is finalized when the `AVAudioFile` is
/// released; if no audio was written, it is deleted, so a file that exists is
/// a playable file.
@available(iOS 15.0, *)
final class AudioFileRecorder {
  static let bitRate = 64_000

  private let url: URL
  private let queue = DispatchQueue(label: "sound_recognition.recording")

  // Everything below is touched only on `queue` (and in init, before any
  // other thread can see the recorder).
  private var file: AVAudioFile?
  private var converter: AVAudioConverter?
  private var framesWritten: AVAudioFramePosition = 0
  private var finished = false

  /// Opens `path` for writing, replacing any file there. Returns nil, having
  /// logged why, if it cannot.
  ///
  /// The file takes the input's own sample rate when that is 22.05–48 kHz,
  /// so the usual mono 48 kHz mic is written with no conversion at all, and
  /// 44.1 kHz otherwise. Below 22.05 kHz Apple's AAC encoder refuses
  /// 64 kbps (measured on macOS: 16 kHz tops out at 48 kbps, 8 kHz takes only
  /// its default), and resampling up costs less than a second code path.
  /// Should the encoder refuse 64 kbps anyway, its default bit rate is tried.
  init?(path: String, inputFormat: AVAudioFormat) {
    url = URL(fileURLWithPath: path)
    let inputRate = inputFormat.sampleRate
    let sampleRate = (22_050...48_000).contains(inputRate) ? inputRate : 44_100
    let settings: [String: Any] = [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: 1,
    ]
    var lastError: Error?
    for bitRate in [Self.bitRate, nil] {
      try? FileManager.default.removeItem(at: url)
      var attempt = settings
      if let bitRate { attempt[AVEncoderBitRateKey] = bitRate }
      do {
        // The container is chosen from the extension, which Dart has
        // already held to .m4a.
        file = try AVAudioFile(
          forWriting: url, settings: attempt, commonFormat: .pcmFormatFloat32,
          interleaved: false)
        return
      } catch {
        lastError = error
      }
    }
    NSLog("sound_recognition: not recording to %@; classification continues without it: %@",
          path, lastError?.localizedDescription ?? "unknown error")
    try? FileManager.default.removeItem(at: url)
    return nil
  }

  /// Queues a tap buffer. Safe from the audio thread; dropped once finished.
  func write(_ buffer: AVAudioPCMBuffer) {
    queue.async { [self] in
      guard !finished, let file else { return }
      do {
        let out = try buffer.format == file.processingFormat
          ? buffer : convert(buffer, to: file.processingFormat)
        guard out.frameLength > 0 else { return }
        try file.write(from: out)
        framesWritten += AVAudioFramePosition(out.frameLength)
      } catch {
        NSLog("sound_recognition: recording to %@ failed; keeping what was written: %@",
              url.path, error.localizedDescription)
        finishOnQueue()
      }
    }
  }

  /// Ends the recording and finalizes the file, without waiting. Idempotent.
  func finish() {
    queue.async { [self] in finishOnQueue() }
  }

  /// Ends the recording and returns once the file is finalized, after any
  /// buffers already queued have been written.
  func finishAndWait() {
    queue.sync { finishOnQueue() }
  }

  private func finishOnQueue() {
    guard !finished else { return }
    finished = true
    flushConverter()
    // Releasing the only reference closes the file and writes the m4a's
    // index; until then it is not playable.
    file = nil
    converter = nil
    if framesWritten == 0 {
      try? FileManager.default.removeItem(at: url)
      NSLog("sound_recognition: no audio arrived for %@; no file written", url.path)
    }
  }

  /// Converts a tap buffer to the file's mono float format. The converter is
  /// rebuilt when the tap's format changes — a route change rebuilds the tap
  /// against the new input, but the file keeps its rate.
  private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws
    -> AVAudioPCMBuffer
  {
    if converter?.inputFormat != buffer.format {
      flushConverter()
      guard let made = AVAudioConverter(from: buffer.format, to: format) else {
        throw Self.error("No converter from \(buffer.format) to \(format)")
      }
      made.downmix = true
      converter = made
    }
    guard let converter else { throw Self.error("No converter") }
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
    guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
      throw Self.error("Could not allocate a conversion buffer")
    }
    // Hand the converter this one buffer, then say "no more for now" rather
    // than "end of stream", so a resampler keeps its state for the next one.
    var supplied = false
    var conversionError: NSError?
    let status = converter.convert(to: out, error: &conversionError) { _, inputStatus in
      if supplied {
        inputStatus.pointee = .noDataNow
        return nil
      }
      supplied = true
      inputStatus.pointee = .haveData
      return buffer
    }
    if status == .error {
      throw conversionError ?? Self.error("Conversion failed")
    }
    return out
  }

  /// Writes out what a resampler is still holding. Without this the last
  /// part of a buffer never reaches the file: measured on macOS, 16 kHz to
  /// 44.1 kHz dropped up to 0.16 s at the end of a clip.
  private func flushConverter() {
    guard let converter, let file else { return }
    self.converter = nil
    let format = converter.outputFormat
    for _ in 0..<8 {  // a bound, not an expectation: one pass is typical
      guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else { return }
      var conversionError: NSError?
      let status = converter.convert(to: out, error: &conversionError) { _, inputStatus in
        inputStatus.pointee = .endOfStream
        return nil
      }
      if out.frameLength > 0 {
        do {
          try file.write(from: out)
          framesWritten += AVAudioFramePosition(out.frameLength)
        } catch {
          return
        }
      }
      if status != .haveData { return }
    }
  }

  private static func error(_ message: String) -> NSError {
    NSError(
      domain: "sound_recognition", code: 2,
      userInfo: [NSLocalizedDescriptionKey: message])
  }
}
