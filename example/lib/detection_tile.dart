part of 'live_page.dart';

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
