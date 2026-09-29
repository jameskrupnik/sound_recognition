import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sound_recognition/sound_recognition.dart';
import 'package:sound_recognition_example/main.dart';

void main() {
  testWidgets('says so when the platform has no classifier', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SoundRecognition.methodChannel,
      (call) async => call.method == 'isSupported' ? false : null,
    );
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('needs iOS 15'), findsOneWidget);
  });

  testWidgets('asks for the microphone before showing the tabs',
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SoundRecognition.methodChannel,
      (call) async => switch (call.method) {
        'isSupported' => true,
        'permissionStatus' => 'undetermined',
        _ => throw PlatformException(code: 'UNEXPECTED'),
      },
    );
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();
    expect(find.text('Allow microphone'), findsOneWidget);
  });
}
