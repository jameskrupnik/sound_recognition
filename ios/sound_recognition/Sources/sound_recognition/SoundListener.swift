import AVFoundation
import SoundAnalysis
import UIKit

/// Microphone to Apple's built-in classifier to callbacks.
///
/// ### The audio session, and why it is `.playAndRecord` + `.mixWithOthers`
///
/// The first consumer is a game with its own music and sound effects, so the
/// one outcome to avoid is the game going silent the moment it starts
/// listening. That rules out `.record` (which silences all playback) and
/// leaves `.playAndRecord`, with three options:
///
///  - `.mixWithOthers` — the app's own audio and other apps' audio keep
///    playing. Without it, activating the session would stop background music
///    from another app, which a kids' game has no business doing.
///  - `.defaultToSpeaker` — `.playAndRecord` otherwise routes output to the
///    *earpiece*, and the game would suddenly sound like a phone call.
///  - `.allowBluetoothA2DP` — keeps Bluetooth headphones in their high-quality
///    output profile; input then comes from the phone's mic. `.allowBluetooth`
///    (HFP) was left out on purpose: it would drop the headphones to
///    call-quality audio to use their mic.
///
/// The costs: the game's audio is now also heard by the classifier (a game
/// whose sound effect is a dog bark will find a dog), and
/// `.playAndRecord` applies voice processing on some routes, lowering playback
/// volume slightly. The previous category is restored on [stop]. And if the
/// game's own audio plugin sets the category itself *after* this starts — a
/// plain `.playback`, say — recording stops; configure it to `.playAndRecord`
/// too, or start listening after it has set its category.
///
/// ### Recording
///
/// With `recordTo`, the tap's buffers also go to an [AudioFileRecorder]: the
/// same capture the classifier reads, not a second recorder. The recording
/// ends at the first interruption and on [stop]. An m4a cannot be appended
/// to, and finalizing at the interruption means an app killed during a phone
/// call still leaves a playable file. A route change is not an interruption:
/// the tap is rebuilt and the recording carries on.
///
/// ### Timestamps
///
/// A result's time is when its window began, in milliseconds since this
/// listener was created — since this `start()` began listening, so each
/// `start()` counts from zero again. Each engine run's results are offset by
/// the wall-clock time from then to the run's start, so times keep rising
/// across an interruption and include the time spent interrupted. Android
/// follows the same rule.
@available(iOS 15.0, *)
final class SoundListener: NSObject {
  private let minConfidence: Double
  private let overlap: Double
  private let recordTo: String?
  private let onEvent: ([String: Any]) -> Void
  private let onError: (String, String) -> Void

  private var engine = AVAudioEngine()
  private var analyzer: SNAudioStreamAnalyzer?
  /// The current run's observer. The analyzer does not keep it alive.
  private var runObserver: RunObserver?
  private let analysisQueue = DispatchQueue(label: "sound_recognition.analysis")
  private var observers: [NSObjectProtocol] = []
  /// Read and written on the main thread only; the tap captures its own copy.
  private var recorder: AudioFileRecorder?
  private var savedSession: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?

  private let startedAt = Date()
  private var interrupted = false
  private var stopped = false

  init(
    minConfidence: Double, overlap: Double, recordTo: String?,
    onEvent: @escaping ([String: Any]) -> Void,
    onError: @escaping (String, String) -> Void
  ) {
    self.minConfidence = minConfidence
    self.overlap = overlap
    self.recordTo = recordTo
    self.onEvent = onEvent
    self.onError = onError
  }

  func start() throws {
    let session = AVAudioSession.sharedInstance()
    savedSession = (session.category, session.mode, session.categoryOptions)
    try activateSession()
    observe()
    if let recordTo {
      // Nil when the file cannot be created: listening goes on without it.
      recorder = AudioFileRecorder(
        path: recordTo, inputFormat: engine.inputNode.outputFormat(forBus: 0))
    }
    try startEngine()
  }

  /// Finalizes the recording, if any, without waiting.
  private func endRecording() {
    recorder?.finish()
    recorder = nil
  }

  private func activateSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord, mode: .default,
      options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
    try session.setActive(true)
  }

  func stop() {
    guard !stopped else { return }
    stopped = true
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    stopEngine()
    // Waits, so the file is playable by the time Dart's cancel completes.
    recorder?.finishAndWait()
    recorder = nil
    // Put the game's category back, but do not deactivate the session: that
    // would stop the game's own audio mid-sound.
    if let (category, mode, options) = savedSession {
      try? AVAudioSession.sharedInstance().setCategory(category, mode: mode, options: options)
    }
  }

  // MARK: - Engine

  private func startEngine() throws {
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw NSError(
        domain: "sound_recognition", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "No audio input is available"])
    }
    let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
    // 0.975 s to match YAMNet's fixed window on Android, so a threshold and a
    // latency mean the same thing on both. Apple's default is 3 s, which
    // measured *worse* on short sounds: a ring or a whistle is diluted by the
    // silence around it (see the README's measurements).
    request.windowDuration = CMTime(value: 975, timescale: 1000)
    request.overlapFactor = overlap
    let analyzer = SNAudioStreamAnalyzer(format: format)
    // Results' time ranges are relative to this run. The offset is fixed per
    // run, in the run's own observer, rather than read from a property when
    // a result arrives: the results `completeAnalysis()` flushes from the
    // previous run arrive after the next run has started, and would otherwise
    // be stamped with the new run's offset.
    let observer = RunObserver(
      listener: self, offset: Date().timeIntervalSince(startedAt))
    try analyzer.add(request, withObserver: observer)
    self.analyzer = analyzer
    runObserver = observer

    // Frame positions are counted here from zero rather than taken from the
    // tap's `when`, so each run's time ranges start at zero and the analyzer
    // sees a strictly increasing position whatever the hardware clock does.
    var framePosition: AVAudioFramePosition = 0
    let recorder = self.recorder
    input.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, _ in
      guard let self else { return }
      recorder?.write(buffer)
      self.analysisQueue.async {
        analyzer.analyze(buffer, atAudioFramePosition: framePosition)
        framePosition += AVAudioFramePosition(buffer.frameLength)
      }
    }
    engine.prepare()
    try engine.start()
    interrupted = false
    onEvent(["event": "state", "state": "listening"])
  }

  private func stopEngine() {
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    if let analyzer {
      // Holds the run's observer until the last of its results are out.
      let observer = runObserver
      analysisQueue.async {
        analyzer.completeAnalysis()
        withExtendedLifetime(observer) {}
      }
    }
    analyzer = nil
    runObserver = nil
  }

  /// Tears the pipeline down and builds it again against whatever the input
  /// is now. Needed after a route change — a headset mic can arrive at a
  /// different sample rate, and a tap installed with the old format fails.
  private func restart() {
    guard !stopped else { return }
    stopEngine()
    do {
      try AVAudioSession.sharedInstance().setActive(true)
      try startEngine()
    } catch {
      // Not fatal yet: another app may still hold the input. Stay
      // interrupted and try again when the app is next active.
      markInterrupted()
    }
  }

  private func markInterrupted() {
    guard !interrupted else { return }
    interrupted = true
    endRecording()
    onEvent(["event": "state", "state": "interrupted"])
  }

  // MARK: - Interruptions

  private func observe() {
    let center = NotificationCenter.default
    func on(_ name: Notification.Name, _ object: Any? = nil, _ block: @escaping (Notification) -> Void) {
      observers.append(center.addObserver(forName: name, object: object, queue: .main, using: block))
    }
    // A phone call, Siri, an alarm: the system stops the engine for us.
    on(AVAudioSession.interruptionNotification) { [weak self] note in
      guard let self,
        let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
        let type = AVAudioSession.InterruptionType(rawValue: raw)
      else { return }
      if type == .began {
        self.stopEngine()
        self.markInterrupted()
      } else {
        // Resume whether or not the system set `.shouldResume`: that flag is
        // advice for media playback, and a listening game wants its ears back.
        self.restart()
      }
    }
    // Headphones in or out, a Bluetooth device connecting: the input format
    // may have changed under the tap. The engine posts this whenever its I/O
    // configuration changes and stops itself; it must be rebuilt.
    // Observed for any engine and filtered here, because a media-services
    // reset replaces `engine` and an observer bound to the old one would go
    // quiet.
    on(.AVAudioEngineConfigurationChange) { [weak self] note in
      guard let self, (note.object as AnyObject?) === self.engine else { return }
      self.restart()
    }
    // The media server crashed. Every audio object is now invalid.
    on(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
      guard let self, !self.stopped else { return }
      // The old engine's encoder state is gone with the media server; keep
      // what was recorded before the reset rather than risk writing on.
      self.endRecording()
      self.analyzer = nil
      self.runObserver = nil
      self.engine = AVAudioEngine()
      do {
        try self.activateSession()
        try self.startEngine()
      } catch {
        self.markInterrupted()
      }
    }
    // The belt to the braces above: an interruption's `.ended` is not
    // guaranteed to arrive (an app that took the mic and was killed never
    // ends it), so returning to the foreground retries.
    on(UIApplication.didBecomeActiveNotification) { [weak self] _ in
      if self?.interrupted == true { self?.restart() }
    }
  }

  // MARK: - Results

  /// Called on the analysis queue with the run's offset.
  fileprivate func deliver(_ result: SNResult, runOffset: TimeInterval) {
    guard let result = result as? SNClassificationResult else { return }
    // Sorted by confidence, so stop at the first one under the floor.
    var labels: [String] = []
    var confidences: [Double] = []
    for c in result.classifications {
      if c.confidence < minConfidence { break }
      labels.append(c.identifier)
      confidences.append(c.confidence)
    }
    guard !labels.isEmpty else { return }
    let timeMs = Int(((runOffset + result.timeRange.start.seconds) * 1000).rounded())
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.stopped else { return }
      self.onEvent([
        "event": "result",
        "classifier": "apple_sound_analysis_v1",
        "timeMs": timeMs,
        "labels": labels,
        "confidences": confidences,
      ])
    }
  }

  fileprivate func fail(_ error: Error) {
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.stopped else { return }
      self.onError("UNKNOWN", error.localizedDescription)
    }
  }
}

/// One engine run's results, stamped with that run's offset.
@available(iOS 15.0, *)
private final class RunObserver: NSObject, SNResultsObserving {
  private weak var listener: SoundListener?
  private let offset: TimeInterval

  init(listener: SoundListener, offset: TimeInterval) {
    self.listener = listener
    self.offset = offset
  }

  func request(_ request: SNRequest, didProduce result: SNResult) {
    listener?.deliver(result, runOffset: offset)
  }

  func request(_ request: SNRequest, didFailWithError error: Error) {
    listener?.fail(error)
  }
}
