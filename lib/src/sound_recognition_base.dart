import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sound_recognition/src/canonical_sound.dart';
import 'package:sound_recognition/src/detection_parser.dart';
import 'package:sound_recognition/src/microphone_permission.dart';
import 'package:sound_recognition/src/sound_detection.dart';
import 'package:sound_recognition/src/sound_listening_state.dart';
import 'package:sound_recognition/src/sound_recognition_exception.dart';

/// On-device sound classification from the microphone.
///
/// ```dart
/// final recognition = SoundRecognition.instance;
/// if (!await recognition.isSupported()) return;
/// if (await recognition.requestPermission() != MicrophonePermission.granted) {
///   return;
/// }
/// final subscription = recognition
///     .start(sounds: {CanonicalSound.doorbell, CanonicalSound.telephone})
///     .listen((detection) => print(detection.sound));
/// ```
///
/// ### Why one instance
///
/// There is one microphone. Both native halves own a single capture pipeline
/// — one `AVAudioEngine` input tap, one `AudioRecord` — and two listeners with
/// two configurations would be two pipelines fighting over it. So
/// [start] *replaces* any stream it handed out before: the old one closes,
/// and the new one gets the new settings.
class SoundRecognition {
  SoundRecognition._();

  /// The one instance. There is one microphone, so there is one listener.
  static final SoundRecognition instance = SoundRecognition._();

  /// The method channel. Exposed only so tests can mock it.
  @visibleForTesting
  static const MethodChannel methodChannel = MethodChannel('sound_recognition');

  /// The detection event channel. Exposed only so tests can mock it.
  @visibleForTesting
  static const EventChannel eventChannel =
      EventChannel('sound_recognition/events');

  StreamController<SoundDetection>? _controller;
  // Cancelled in [_release], through a local: the field is cleared *before*
  // the await so that a [start] racing the cancel installs its own
  // subscription rather than having it nulled underneath it.
  // ignore: cancel_subscriptions
  StreamSubscription<Object?>? _native;

  final StreamController<SoundListeningState> _states =
      StreamController<SoundListeningState>.broadcast();
  SoundListeningState _state = SoundListeningState.stopped;

  /// Whether this device can classify sound at all.
  ///
  /// False on iOS before 15, and on any platform this package does not
  /// implement — rather than throwing, so a game can hide its sound mode with
  /// one check.
  Future<bool> isSupported() async {
    try {
      return await methodChannel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// The microphone permission, without prompting.
  Future<MicrophonePermission> permissionStatus() =>
      _permission('permissionStatus');

  /// Prompts for the microphone if the platform still will, and returns the
  /// outcome. Returns at once, without a prompt, when already decided.
  ///
  /// The prompt's text on iOS is the app's `NSMicrophoneUsageDescription`;
  /// without that key iOS terminates the app at this call, not later.
  Future<MicrophonePermission> requestPermission() =>
      _permission('requestPermission');

  Future<MicrophonePermission> _permission(String method) async {
    final name = await methodChannel.invokeMethod<String>(method);
    return MicrophonePermission.values.firstWhere(
      (p) => p.name == name,
      orElse: () => MicrophonePermission.denied,
    );
  }

  /// Every raw label this platform's classifier can produce — for going past
  /// [CanonicalSound], or for building a picker. About 300 on iOS, 521 on
  /// Android, and the two lists share almost no spellings.
  Future<List<String>> knownLabels() async {
    final labels = await methodChannel.invokeListMethod<String>('knownLabels');
    return labels ?? const [];
  }

  /// The current [SoundListeningState].
  SoundListeningState get state => _state;

  /// Every change to [state]. Broadcast, and does not replay the current
  /// value — read [state] first.
  Stream<SoundListeningState> get stateChanges => _states.stream;

  /// Starts classifying the microphone and returns the detections.
  ///
  /// Listening begins when the stream is listened to and ends when that
  /// subscription is cancelled, [stop] is called, or [start] is called again.
  /// A failure arrives as a [SoundRecognitionException] on the stream, after
  /// which it closes.
  ///
  /// [minConfidence] is the floor under which a label is not reported. The
  /// default suits a game that would rather miss a sound than invent one;
  /// see [SoundDetection.confidence] for why it is worth tuning per platform.
  ///
  /// [overlap] is how much consecutive windows share. Every window is 0.975 s
  /// on both platforms — YAMNet's is fixed there, and iOS is set to match — so
  /// 0.5 means a result about every half second. Higher is more responsive
  /// and costs proportionally more inference.
  ///
  /// With neither [sounds] nor [rawLabels], every label that clears the floor
  /// is reported. With either, only detections whose [SoundDetection.sound]
  /// is in [sounds] *or* whose raw label is in [rawLabels].
  Stream<SoundDetection> start({
    double minConfidence = 0.5,
    double overlap = 0.5,
    Set<CanonicalSound>? sounds,
    Set<String>? rawLabels,
  }) {
    if (minConfidence < 0.01 || minConfidence > 1) {
      throw ArgumentError.value(
        minConfidence,
        'minConfidence',
        'must be from 0.01 to 1',
      );
    }
    // Capped below 1: at 1 there is no hop, and the next window never comes.
    if (overlap < 0 || overlap > 0.9) {
      throw ArgumentError.value(overlap, 'overlap', 'must be from 0 to 0.9');
    }
    unawaited(stop());

    bool wanted(SoundDetection d) =>
        (sounds == null && rawLabels == null) ||
        (sounds?.contains(d.sound) ?? false) ||
        (rawLabels?.contains(d.rawLabel) ?? false);

    late final StreamController<SoundDetection> controller;
    controller = StreamController<SoundDetection>(
      onListen: () {
        // A stream that [start] or [stop] has already replaced is closed, but
        // a closed controller still runs onListen for a late listener. Opening
        // the channel here would take over the live stream's native session
        // with stale settings, and this controller's onCancel would then
        // never release it.
        if (!identical(_controller, controller)) return;
        _native = eventChannel.receiveBroadcastStream({
          'minConfidence': minConfidence,
          'overlap': overlap,
        }).listen(
          (event) => _onEvent(event, controller, wanted),
          onError: (Object error, StackTrace stackTrace) {
            controller.addError(
              SoundRecognitionException.from(error),
              stackTrace,
            );
            if (identical(_controller, controller)) unawaited(stop());
          },
        );
      },
      onCancel: () {
        if (identical(_controller, controller)) return _release();
        return null;
      },
    );
    _controller = controller;
    return controller.stream;
  }

  void _onEvent(
    Object? event,
    StreamController<SoundDetection> controller,
    bool Function(SoundDetection) wanted,
  ) {
    if (event is! Map<Object?, Object?>) return;
    switch (event['event']) {
      case 'result':
        DetectionParser.parse(event).where(wanted).forEach(controller.add);
      case 'state':
        final state = SoundListeningState.values.firstWhere(
          (s) => s.name == event['state'],
          orElse: () => _state,
        );
        _setState(state);
    }
  }

  /// Stops listening and closes the stream [start] returned. Safe to call
  /// when not listening.
  Future<void> stop() async {
    final controller = _controller;
    await _release();
    // Not awaited: a controller nobody ever listened to never delivers its
    // done event, so its close() future would never complete.
    unawaited(controller?.close());
  }

  Future<void> _release() async {
    final native = _native;
    _controller = null;
    _native = null;
    _setState(SoundListeningState.stopped);
    await native?.cancel();
  }

  void _setState(SoundListeningState state) {
    if (state == _state) return;
    _state = state;
    _states.add(state);
  }

  /// Test seam: drop any active stream without talking to the platform, so
  /// one test's listener cannot leak into the next through [instance].
  @visibleForTesting
  void debugReset() {
    _controller = null;
    _native = null;
    _state = SoundListeningState.stopped;
  }
}
