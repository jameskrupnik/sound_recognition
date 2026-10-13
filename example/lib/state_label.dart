part of 'live_page.dart';

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
