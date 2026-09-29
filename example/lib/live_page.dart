import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sound_recognition/sound_recognition.dart';

/// Every label that clears the floor, newest first, canonical or not.
class LivePage extends StatefulWidget {
  /// Creates the live detections page.
  const LivePage({super.key});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  static const _kept = 60;

  final List<SoundDetection> _detections = [];
  StreamSubscription<SoundDetection>? _subscription;
  String? _error;

  bool get _listening => _subscription != null;

  void _toggle() {
    if (_listening) {
      _stop();
      return;
    }
    setState(() => _error = null);
    _subscription = SoundRecognition.instance.start(minConfidence: 0.3).listen(
          (d) => setState(() {
            _detections.insert(0, d);
            if (_detections.length > _kept) _detections.removeLast();
          }),
          onError: (Object e) => setState(() => _error = e.toString()),
          onDone: () => setState(() => _subscription = null),
        );
    setState(() {});
  }

  void _stop() {
    unawaited(_subscription?.cancel());
    setState(() => _subscription = null);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: _toggle,
                icon: Icon(_listening ? Icons.stop : Icons.mic),
                label: Text(_listening ? 'Stop' : 'Listen'),
              ),
              const SizedBox(width: 12),
              const Expanded(child: _StateLabel()),
            ],
          ),
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _detections.length,
            itemBuilder: (context, i) => _DetectionTile(_detections[i]),
          ),
        ),
      ],
    );
  }
}

class _StateLabel extends StatelessWidget {
  const _StateLabel();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SoundListeningState>(
      stream: SoundRecognition.instance.stateChanges,
      initialData: SoundRecognition.instance.state,
      builder: (context, snapshot) => Text(snapshot.requireData.name),
    );
  }
}

class _DetectionTile extends StatelessWidget {
  const _DetectionTile(this.detection);

  final SoundDetection detection;

  @override
  Widget build(BuildContext context) {
    final seconds = detection.timestamp.inMilliseconds / 1000;
    return ListTile(
      dense: true,
      title: Text(detection.sound?.displayName ?? '(not canonical)'),
      subtitle: Text('${detection.rawLabel} · ${seconds.toStringAsFixed(1)} s'),
      trailing: SizedBox(
        width: 72,
        child: LinearProgressIndicator(value: detection.confidence),
      ),
    );
  }
}
