import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sound_recognition/sound_recognition.dart';
import 'package:sound_recognition_example/hunt_page.dart';

void main() {
  late MockStreamHandlerEventSink? sink;

  setUp(() {
    sink = null;
    SoundRecognition.instance.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      SoundRecognition.eventChannel,
      MockStreamHandler.inline(
        onListen: (_, events) {
          sink = events;
        },
      ),
    );
  });

  Future<void> pumpHunt(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HuntPage())),
    );
    await tester.tap(find.text('Listen'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    expect(sink, isNotNull);
    expect(find.text('Listening…'), findsOneWidget);
  }

  FilledButton listenButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Listen'));

  testWidgets('an error is shown and Listen works again', (tester) async {
    await pumpHunt(tester);
    // Channel traffic is real async, outside the test's fake clock.
    await tester.runAsync(() async {
      sink!.error(code: 'AUDIO_UNAVAILABLE', message: 'mic busy');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
    expect(find.textContaining('mic busy'), findsOneWidget);
    expect(find.text('Listening…'), findsNothing);
    expect(listenButton(tester).onPressed, isNotNull);
  });

  testWidgets('a stream ended elsewhere re-enables Listen', (tester) async {
    await pumpHunt(tester);
    // Another screen (or app code) calling stop() ends this stream.
    await tester.runAsync(SoundRecognition.instance.stop);
    await tester.pump();
    expect(find.text('Listening…'), findsNothing);
    expect(listenButton(tester).onPressed, isNotNull);
  });
}
