import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sound_recognition/sound_recognition.dart';
import 'package:sound_recognition_example/hunt_page.dart';
import 'package:sound_recognition_example/live_page.dart';

part 'app_bar.dart';
part 'main_gate.dart';

void main() => runApp(const ExampleApp());

/// Two tabs over one [SoundRecognition]: every label as it arrives, and a
/// one-sound-at-a-time hunt — the shape of the game this package was built
/// for.
///
/// Both tabs call `start`, and since there is one microphone the second
/// replaces the first. Switching tabs therefore stops whichever was running,
/// which is also what a game switching modes should do.
class ExampleApp extends StatelessWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'sound_recognition',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      home: const DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: _AppBar(),
          body: _Gate(
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [LivePage(), HuntPage()],
            ),
          ),
        ),
      ),
    );
  }
}
