import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sound_recognition/sound_recognition.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final recognition = SoundRecognition.instance;

  final calls = <MethodCall>[];
  late List<Object?> listens;
  late int cancels;
  // The native side's end of the event channel, captured on listen so a test
  // can push events through the real codec and routing.
  MockStreamHandlerEventSink? sink;

  Map<String, Object?> result(List<String> labels, List<double> confidences) =>
      {
        'event': 'result',
        'classifier': 'yamnet',
        'timeMs': 500,
        'labels': labels,
        'confidences': confidences,
      };

  setUp(() {
    calls.clear();
    listens = [];
    cancels = 0;
    sink = null;
    recognition.debugReset();
    messenger
      ..setMockMethodCallHandler(SoundRecognition.methodChannel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'isSupported' => true,
          'permissionStatus' => 'undetermined',
          'requestPermission' => 'granted',
          'knownLabels' => ['Speech', 'Bark'],
          _ => null,
        };
      })
      ..setMockStreamHandler(
        SoundRecognition.eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            listens.add(arguments);
            sink = events;
          },
          onCancel: (_) => cancels++,
        ),
      );
  });

  group('method calls', () {
    test('isSupported passes the platform answer through', () async {
      expect(await recognition.isSupported(), isTrue);
    });

    test('isSupported is false, not a throw, with no plugin', () async {
      messenger.setMockMethodCallHandler(SoundRecognition.methodChannel, null);
      expect(await recognition.isSupported(), isFalse);
    });

    test('permission names map onto the enum', () async {
      expect(
        await recognition.permissionStatus(),
        MicrophonePermission.undetermined,
      );
      expect(
        await recognition.requestPermission(),
        MicrophonePermission.granted,
      );
    });

    test('an unknown permission name reads as denied', () async {
      messenger.setMockMethodCallHandler(
        SoundRecognition.methodChannel,
        (_) async => 'provisional',
      );
      expect(
        await recognition.permissionStatus(),
        MicrophonePermission.denied,
      );
    });

    test('knownLabels returns the raw vocabulary', () async {
      expect(await recognition.knownLabels(), ['Speech', 'Bark']);
    });
  });

  group('start', () {
    test('does nothing native until the stream is listened to', () async {
      final stream = recognition.start();
      await pumpEventQueue();
      expect(listens, isEmpty);
      final sub = stream.listen((_) {});
      await pumpEventQueue();
      expect(listens.single, {'minConfidence': 0.5, 'overlap': 0.5});
      await sub.cancel();
    });

    test('sends its settings to the platform', () async {
      final sub =
          recognition.start(minConfidence: 0.3, overlap: 0.75).listen((_) {});
      await pumpEventQueue();
      expect(listens.single, {'minConfidence': 0.3, 'overlap': 0.75});
      await sub.cancel();
    });

    test('rejects settings out of range', () {
      expect(() => recognition.start(minConfidence: 0), throwsArgumentError);
      expect(() => recognition.start(overlap: 1), throwsArgumentError);
    });

    test('delivers every label when unfiltered', () async {
      final got = <SoundDetection>[];
      final sub = recognition.start().listen(got.add);
      await pumpEventQueue();
      sink!.success(result(['Bark', 'Theremin'], [0.9, 0.6]));
      await pumpEventQueue();
      expect(got.map((d) => d.sound), [CanonicalSound.dog, null]);
      await sub.cancel();
    });

    test('filters to canonical sounds and raw labels, as a union', () async {
      final got = <SoundDetection>[];
      final sub = recognition.start(
        sounds: {CanonicalSound.dog},
        rawLabels: {'Theremin'},
      ).listen(got.add);
      await pumpEventQueue();
      sink!.success(
        result(['Bark', 'Music', 'Theremin', 'Dog'], [0.9, 0.8, 0.7, 0.6]),
      );
      await pumpEventQueue();
      expect(got.map((d) => d.rawLabel), ['Bark', 'Theremin', 'Dog']);
      await sub.cancel();
    });

    test('tracks state events and returns to stopped on cancel', () async {
      final states = <SoundListeningState>[];
      final stateSub = recognition.stateChanges.listen(states.add);
      final sub = recognition.start().listen((_) {});
      await pumpEventQueue();
      sink!
        ..success({'event': 'state', 'state': 'listening'})
        ..success({'event': 'state', 'state': 'interrupted'})
        ..success({'event': 'state', 'state': 'listening'});
      await pumpEventQueue();
      expect(recognition.state, SoundListeningState.listening);
      await sub.cancel();
      await pumpEventQueue();
      expect(states, [
        SoundListeningState.listening,
        SoundListeningState.interrupted,
        SoundListeningState.listening,
        SoundListeningState.stopped,
      ]);
      expect(cancels, 1);
      await stateSub.cancel();
    });

    test('a native error arrives typed, then the stream closes', () async {
      final errors = <Object>[];
      final done = Completer<void>();
      recognition.start().listen(
            (_) {},
            onError: errors.add,
            onDone: done.complete,
          );
      await pumpEventQueue();
      sink!.error(code: 'PERMISSION_DENIED', message: 'no mic');
      await done.future.timeout(const Duration(seconds: 1));
      final error = errors.single as SoundRecognitionException;
      expect(error.code, SoundRecognitionErrorCode.permissionDenied);
      expect(error.message, 'no mic');
      expect(cancels, 1);
    });

    test('an unknown error code maps to unknown', () {
      final e = SoundRecognitionException.from(
        PlatformException(code: 'SOMETHING_NEW'),
      );
      expect(e.code, SoundRecognitionErrorCode.unknown);
    });

    test('a second start closes the first stream', () async {
      final firstDone = Completer<void>();
      recognition.start().listen((_) {}, onDone: firstDone.complete);
      await pumpEventQueue();
      final second = recognition.start(minConfidence: 0.8).listen((_) {});
      await firstDone.future.timeout(const Duration(seconds: 1));
      await pumpEventQueue();
      expect(listens.last, {'minConfidence': 0.8, 'overlap': 0.5});
      await second.cancel();
    });

    test('stop closes the stream and cancels native', () async {
      final done = Completer<void>();
      recognition.start().listen((_) {}, onDone: done.complete);
      await pumpEventQueue();
      await recognition.stop();
      await done.future.timeout(const Duration(seconds: 1));
      expect(cancels, 1);
      expect(recognition.state, SoundListeningState.stopped);
    });

    test('a stream replaced before it was listened to never opens the mic',
        () async {
      final stale = recognition.start();
      final current = recognition.start(minConfidence: 0.8).listen((_) {});
      await pumpEventQueue();
      expect(listens, hasLength(1));

      final staleDone = Completer<void>();
      stale.listen((_) {}, onDone: staleDone.complete);
      await staleDone.future.timeout(const Duration(seconds: 1));
      await pumpEventQueue();
      // The live stream's native subscription is untouched: one listen, and
      // cancelling the live stream still reaches the platform.
      expect(listens, hasLength(1));
      await current.cancel();
      await pumpEventQueue();
      expect(cancels, 1);
    });

    test('a stream stopped before it was listened to never opens the mic',
        () async {
      final stale = recognition.start();
      await recognition.stop();
      final done = Completer<void>();
      stale.listen((_) {}, onDone: done.complete);
      await done.future.timeout(const Duration(seconds: 1));
      await pumpEventQueue();
      expect(listens, isEmpty);
      expect(recognition.state, SoundListeningState.stopped);
    });

    test('stop is safe when nothing is listening', () async {
      await recognition.stop();
      await recognition.start().listen((_) {}).cancel();
      await recognition.stop();
    });
  });
}
