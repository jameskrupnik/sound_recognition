import AVFoundation
import Flutter
import SoundAnalysis
import UIKit

/// The iOS half: a method channel for permission and metadata, and an event
/// channel whose listen/cancel *is* start/stop.
///
/// Tying the microphone to the event-channel subscription means there is no
/// state in which Dart has stopped listening and the mic is still on:
/// cancelling the Dart stream is enough. The one gap is a debug-only hot
/// restart: it does not cancel channel streams, and iOS gives plugins no
/// restart hook (Android's does, and uses it), so the mic stays on until the
/// restarted app next calls `start()` — which cancels the old session first.
public class SoundRecognitionPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  /// A `SoundListener` on iOS 15+. Typed `AnyObject` because a stored
  /// property cannot be `@available`-gated, and the plugin itself must load
  /// on iOS 13 to answer `isSupported` with false.
  private var listener: AnyObject?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SoundRecognitionPlugin()
    let methods = FlutterMethodChannel(
      name: "sound_recognition", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)
    let events = FlutterEventChannel(
      name: "sound_recognition/events", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      if #available(iOS 15.0, *) { result(true) } else { result(false) }
    case "permissionStatus":
      result(Self.permissionStatus())
    case "requestPermission":
      Self.requestPermission { granted in
        DispatchQueue.main.async { result(granted ? "granted" : Self.permissionStatus()) }
      }
    case "knownLabels":
      if #available(iOS 15.0, *) {
        result((try? SNClassifySoundRequest(classifierIdentifier: .version1))?
          .knownClassifications ?? [])
      } else {
        result([String]())
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Listening

  public func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    stopListening()
    // Failures go down the sink, not back as the return value: Flutter's Dart
    // side reports an error *returned* from onListen to FlutterError.onError
    // and never delivers it to the stream the caller is listening on.
    guard #available(iOS 15.0, *) else {
      events(FlutterError(code: "UNSUPPORTED", message: "Needs iOS 15", details: nil))
      return nil
    }
    guard Self.permissionStatus() == "granted" else {
      events(FlutterError(
        code: "PERMISSION_DENIED", message: "Microphone permission is not granted", details: nil))
      return nil
    }
    let args = arguments as? [String: Any] ?? [:]
    let listener = SoundListener(
      minConfidence: (args["minConfidence"] as? NSNumber)?.doubleValue ?? 0.5,
      overlap: (args["overlap"] as? NSNumber)?.doubleValue ?? 0.5,
      recordTo: args["recordTo"] as? String,
      onEvent: { events($0) },
      onError: { [weak self] code, message in
        events(FlutterError(code: code, message: message, details: nil))
        self?.stopListening()
      })
    do {
      try listener.start()
      self.listener = listener
    } catch {
      listener.stop()
      events(FlutterError(
        code: "AUDIO_UNAVAILABLE", message: error.localizedDescription, details: nil))
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stopListening()
    return nil
  }

  private func stopListening() {
    if #available(iOS 15.0, *) { (listener as? SoundListener)?.stop() }
    listener = nil
  }

  // MARK: - Permission

  /// iOS has exactly the three states the Dart enum has. A denial is final
  /// from the app's side — the system never prompts twice — so `denied` here
  /// always means "only Settings can change this".
  private static func permissionStatus() -> String {
    if #available(iOS 17.0, *) {
      switch AVAudioApplication.shared.recordPermission {
      case .granted: return "granted"
      case .denied: return "denied"
      default: return "undetermined"
      }
    }
    switch AVAudioSession.sharedInstance().recordPermission {
    case .granted: return "granted"
    case .denied: return "denied"
    default: return "undetermined"
    }
  }

  private static func requestPermission(_ done: @escaping (Bool) -> Void) {
    if #available(iOS 17.0, *) {
      AVAudioApplication.requestRecordPermission(completionHandler: done)
    } else {
      AVAudioSession.sharedInstance().requestRecordPermission(done)
    }
  }
}
