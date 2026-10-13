part of 'main.dart';

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
    final permission = supported
        ? await SoundRecognition.instance.permissionStatus()
        : null;
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
      _ =>
        'This demo listens to the microphone. Nothing is sent anywhere, '
            'and audio is saved only when you turn on Save audio.',
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
