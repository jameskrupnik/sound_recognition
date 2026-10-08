import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sound_recognition/sound_recognition.dart';
import 'package:sound_recognition_example/live_page.dart';

MockStreamHandlerEventSink? _sink;
List<Object?> _listens = [];

Future<void> _settleChannel(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  await tester.pump();
}

Future<void> _pumpLive(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LivePage(recordingPath: () async => '/tmp/live-test.m4a'),
      ),
    ),
  );
}

void _detect(String label, int timeMs) => _sink!.success({
      'event': 'result',
      'classifier': 'yamnet',
      'timeMs': timeMs,
      'labels': [label],
      'confidences': [0.9],
    });

void main() {
  setUp(() {
    _sink = null;
    _listens = [];
    SoundRecognition.instance.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      SoundRecognition.eventChannel,
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          _listens.add(arguments);
          _sink = events;
        },
      ),
    );
  });

  testWidgets('each Listen starts a fresh list', (tester) async {
    await _pumpLive(tester);
    await tester.tap(find.text('Listen'));
    await _settleChannel(tester);
    _detect('Siren', 32200);
    await _settleChannel(tester);
    expect(find.textContaining('32.2 s'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await _settleChannel(tester);
    await tester.tap(find.text('Listen'));
    await _settleChannel(tester);
    // Timestamps restart with each start(); an old session's rows left
    // above them read as if the clock had carried on.
    expect(find.textContaining('32.2 s'), findsNothing);
    _detect('Speech', 500);
    await _settleChannel(tester);
    expect(find.textContaining('0.5 s'), findsOneWidget);
  });

  testWidgets('Save audio passes recordTo, and only when on', (tester) async {
    await _pumpLive(tester);
    await tester.tap(find.text('Listen'));
    await _settleChannel(tester);
    expect((_listens.last! as Map)['recordTo'], isNull);
    await tester.tap(find.text('Stop'));
    await _settleChannel(tester);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('Listen'));
    await _settleChannel(tester);
    expect((_listens.last! as Map)['recordTo'], '/tmp/live-test.m4a');
    expect(find.byType(Switch), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
  });
}
