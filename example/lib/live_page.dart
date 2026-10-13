import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sound_recognition/sound_recognition.dart';

part 'detection_tile.dart';
part 'state_label.dart';

/// Where the Live tab saves audio when "Save audio" is on.
///
/// On Android this is the app's external files directory, so the file can be
/// pulled with `adb pull /sdcard/Android/data/<package>/files/live.m4a`
/// without `run-as`; on iOS, the app's Documents directory.
Future<String> defaultRecordingPath() async {
  final dir = Platform.isAndroid
      ? await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory()
      : await getApplicationDocumentsDirectory();
  return '${dir.path}/live.m4a';
}

/// Every label that clears the floor, newest first, canonical or not.
///
/// With "Save audio" on, the session is also recorded through `recordTo` —
/// the same audio the classifier heard, which is the way to tell a sound the
/// microphone never picked up from one the classifier missed.
class LivePage extends StatefulWidget {
  /// Creates the live detections page.
  const LivePage({super.key, this.recordingPath = defaultRecordingPath});

  /// Where to record when "Save audio" is on.
  final Future<String> Function() recordingPath;

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  static const _kept = 60;

  final List<SoundDetection> _detections = [];
  StreamSubscription<SoundDetection>? _subscription;
  String? _error;
  bool _save = false;
  String? _savedTo;
  String? _saved;

  bool get _listening => _subscription != null;

  Future<void> _toggle() async {
    if (_listening) return _stop();
    final path = _save ? await widget.recordingPath() : null;
    if (!mounted) return;
    setState(() {
      _error = null;
      _saved = null;
      _savedTo = path;
      // Timestamps restart at zero with every start(), so rows from the last
      // session would read as if the clock had carried on.
      _detections.clear();
    });
    _subscription = SoundRecognition.instance
        .start(minConfidence: 0.3, recordTo: path)
        .listen(
          (d) => setState(() {
            _detections.insert(0, d);
            if (_detections.length > _kept) _detections.removeLast();
          }),
          onError: (Object e) => setState(() => _error = e.toString()),
          onDone: () {
            if (mounted) setState(() => _subscription = null);
          },
        );
    setState(() {});
  }

  Future<void> _stop() async {
    final subscription = _subscription;
    setState(() => _subscription = null);
    // The recording is finalized when the cancel completes.
    await subscription?.cancel();
    final path = _savedTo;
    if (path == null || !mounted) return;
    final file = File(path);
    final saved = file.existsSync()
        ? 'Saved ${(file.lengthSync() / 1024).ceil()} KB to $path'
        : 'No recording was left at $path';
    setState(() => _saved = saved);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final saved = _saved;
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
              const Text('Save audio'),
              Switch(
                value: _save,
                onChanged: _listening
                    ? null
                    : (on) => setState(() => _save = on),
              ),
            ],
          ),
        ),
        if (error != null)
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (saved != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SelectableText(saved),
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
