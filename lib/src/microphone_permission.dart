/// The microphone permission, reduced to the one question an app has to
/// answer: will asking show the user a prompt?
///
/// Both platforms have more states than this, and they do not line up —
/// Android has "denied, but you may ask once more", iOS has no such thing.
/// What an app actually does next is one of three things, so that is what
/// this reports.
enum MicrophonePermission {
  /// The app may record.
  granted,

  /// Not granted, and `SoundRecognition.requestPermission` will show the
  /// system prompt. On Android this includes "denied once, may ask again"
  /// and a prompt the user dismissed without answering.
  undetermined,

  /// Not granted, and asking again will not show anything: the user has to
  /// change it in Settings. iOS after any denial; Android after "don't ask
  /// again", or a second denial on Android 11+.
  denied,
}
