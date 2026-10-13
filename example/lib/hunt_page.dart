import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sound_recognition/sound_recognition.dart';

/// The scavenger hunt in miniature: one canonical sound to find, listening
/// only for that sound, and "found it" on the first detection.
///
/// Passing `sounds: {target}` is the point being demonstrated. The game never
/// sees a raw label or a platform name, and the same code finds a doorbell
/// on an iPhone (`door_bell`) and on Android (`Doorbell`, `Ding-dong`).
class HuntPage extends StatefulWidget {
  /// Creates the hunt page.
  const HuntPage({super.key});

  @override
  State<HuntPage> createState() => _HuntPageState();
}

class _HuntPageState extends State<HuntPage> {
  // Things a child can find or make indoors, without leaving the house or
  // waiting for weather.
  static const List<CanonicalSound> _pool = [
    CanonicalSound.clapping,
    CanonicalSound.whistling,
    CanonicalSound.laughter,
    CanonicalSound.singing,
    CanonicalSound.knock,
    CanonicalSound.telephone,
    CanonicalSound.waterTap,
    CanonicalSound.typing,
    CanonicalSound.keysJangling,
    CanonicalSound.crumpling,
    CanonicalSound.dishes,
    CanonicalSound.bell,
  ];

  final _random = Random();
  late CanonicalSound _target = _pool[_random.nextInt(_pool.length)];
  StreamSubscription<SoundDetection>? _subscription;
  SoundDetection? _found;
  String? _error;

  void _listen() {
    setState(() {
      _found = null;
      _error = null;
    });
    // onError and onDone both matter: without them a failure is an uncaught
    // error, and a stream ended elsewhere (the Live tab starting, a stop())
    // leaves this page "Listening…" with its button disabled for good.
    _subscription = SoundRecognition.instance
        .start(minConfidence: 0.4, sounds: {_target})
        .listen(
          (d) {
            unawaited(_subscription?.cancel());
            setState(() {
              _subscription = null;
              _found = d;
            });
          },
          onError: (Object e) => setState(() => _error = e.toString()),
          onDone: () {
            if (mounted) setState(() => _subscription = null);
          },
        );
    setState(() {});
  }

  void _next() {
    unawaited(_subscription?.cancel());
    setState(() {
      _subscription = null;
      _found = null;
      _error = null;
      _target = (_pool.toList()
        ..remove(_target))[_random.nextInt(_pool.length - 1)];
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final found = _found;
    final error = _error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Find something that sounds like…', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(_target.displayName, style: text.displaySmall),
            const SizedBox(height: 24),
            if (found != null)
              Text(
                'Found it! (${found.rawLabel}, '
                '${(found.confidence * 100).round()}%)',
                style: text.titleLarge,
              )
            else if (error != null)
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (_subscription != null)
              const Text('Listening…'),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              children: [
                FilledButton(
                  onPressed: _subscription == null ? _listen : null,
                  child: const Text('Listen'),
                ),
                OutlinedButton(onPressed: _next, child: const Text('Another')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
