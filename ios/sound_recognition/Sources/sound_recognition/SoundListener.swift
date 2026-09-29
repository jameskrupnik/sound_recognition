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
@available(iOS 15.0, *)
final class SoundListener: NSObject, SNResultsObserving {
  private let minConfidence: Double
  private let overlap: Double
  private let onEvent: ([String: Any]) -> Void
  private let onError: (String, String) -> Void

  private var engine = AVAudioEngine()
  private var analyzer: SNAudioStreamAnalyzer?
  private let analysisQueue = DispatchQueue(label: "sound_recognition.analysis")
  private var observers: [NSObjectProtocol] = []
  private var savedSession: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?

  private let startedAt = Date()
  /// Seconds from `startedAt` to the start of the current engine run. Results'
  /// time ranges are relative to the run, so this keeps timestamps rising
  /// across an interruption instead of restarting at zero — the same rule the
  /// Android side follows.
  private var segmentStart: TimeInterval = 0
  private var interrupted = false
  private var stopped = false

  init(
    minConfidence: Double, overlap: Double,
    onEvent: @escaping ([String: Any]) -> Void,
    onError: @escaping (String, String) -> Void
  ) {
    self.minConfidence = minConfidence
    self.overlap = overlap
    self.onEvent = onEvent
    self.onError = onError
  }

  func start() throws {
    let session = AVAudioSession.sharedInstance()
    savedSession = (session.category, session.mode, session.categoryOptions)
    try activateSession()
    observe()
    try startEngine()
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
    try analyzer.add(request, withObserver: self)
    self.analyzer = analyzer
    segmentStart = Date().timeIntervalSince(startedAt)

    // Frame positions are counted here from zero rather than taken from the
    // tap's `when`, so each run's time ranges start at zero and the analyzer
    // sees a strictly increasing position whatever the hardware clock does.
    var framePosition: AVAudioFramePosition = 0
    input.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, _ in
      guard let self else { return }
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
      analysisQueue.async { analyzer.completeAnalysis() }
    }
    analyzer = nil
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
      self.analyzer = nil
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

  // MARK: - SNResultsObserving

  func request(_ request: SNRequest, didProduce result: SNResult) {
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
    let start = result.timeRange.start.seconds
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.stopped else { return }
      self.onEvent([
        "event": "result",
        "classifier": "apple_sound_analysis_v1",
        "timeMs": Int((self.segmentStart + start) * 1000),
        "labels": labels,
        "confidences": confidences,
      ])
    }
  }

  func request(_ request: SNRequest, didFailWithError error: Error) {
    DispatchQueue.main.async { [weak self] in
      guard let self, !self.stopped else { return }
      self.onError("UNKNOWN", error.localizedDescription)
    }
  }
}
