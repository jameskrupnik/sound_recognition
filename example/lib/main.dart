import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sound_recognition/sound_recognition.dart';
import 'package:sound_recognition_example/hunt_page.dart';
import 'package:sound_recognition_example/live_page.dart';

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

class _AppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight * 2);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('sound_recognition'),
      bottom: const TabBar(
        tabs: [Tab(text: 'Live'), Tab(text: 'Hunt')],
      ),
    );
  }
}

/// Holds the tabs back until the device is supported and the microphone is
/// granted, and says which of the two is missing rather than failing later.
class _Gate extends StatefulWidget {
  const _Gate({required this.child});

  final Widget child;

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  bool? _supported;
  MicrophonePermission? _permission;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    final supported = await SoundRecognition.instance.isSupported();
    final permission =
        supported ? await SoundRecognition.instance.permissionStatus() : null;
    if (!mounted) return;
    setState(() {
      _supported = supported;
      _permission = permission;
    });
  }

  Future<void> _request() async {
    final permission = await SoundRecognition.instance.requestPermission();
    if (!mounted) return;
    setState(() => _permission = permission);
  }

  @override
  Widget build(BuildContext context) {
    final message = switch ((_supported, _permission)) {
      (null, _) => null,
      (false, _) => 'Sound recognition needs iOS 15 or Android 7.',
      (_, MicrophonePermission.granted) => null,
      (_, MicrophonePermission.denied) =>
        'Microphone access is off. Turn it on in Settings.',
      _ => 'This demo listens to the microphone. Nothing is recorded or sent '
          'anywhere.',
    };
    if (_supported == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (message == null) return widget.child;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (_permission == MicrophonePermission.undetermined)
              FilledButton(
                onPressed: _request,
                child: const Text('Allow microphone'),
              ),
          ],
        ),
      ),
    );
  }
}
