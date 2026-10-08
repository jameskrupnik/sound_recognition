/// @docImport 'package:sound_recognition/src/sound_labels.dart';
/// @docImport 'package:sound_recognition/src/sound_recognition_base.dart';
library;

/// The broad group a [CanonicalSound] belongs to.
///
/// It exists for the consuming UI — a hunt screen that says "find an animal",
/// a picker grouped into sections — and has no effect on recognition.
enum SoundCategory {
  /// Animals and insects.
  animals,

  /// Sounds a person makes with their voice or body.
  people,

  /// Household objects and appliances.
  home,

  /// Instruments and music.
  music,

  /// Traffic, weather and the outdoors.
  outdoors,
}

/// One sound, named the same way on both platforms.
///
/// This is the vocabulary the package exists to provide. Apple's classifier
/// says `dog_bark`; YAMNet says `Bark`, and also `Dog`, and also `Bow-wow`, in
/// the same second. A game that asks for "a dog" should not have to know
/// either list, so each value here stands for a *set* of raw labels on each
/// platform, and those sets are in [SoundLabels] as data rather than here as
/// code.
///
/// ### How the list was chosen
///
/// Sixty sounds a child can plausibly *find or make* at home, in the yard or
/// on a walk, because the first consumer is a scavenger hunt. Two rules cut
/// it down from the ~300 Apple labels and 521 YAMNet classes:
///
///  - **Every value must map on both platforms.** A hunt item that can only
///    be found on an iPhone is a bug report, so a sound with no counterpart —
///    nose blowing is Apple-only, an ice-cream truck is YAMNet-only — is left
///    to the raw labels instead. A test enforces this.
///  - **Nothing a child should be sent to trigger.** Smoke and fire alarms
///    are in both lists and deliberately absent here.
///
/// Anything outside the sixty is still reachable: every detection carries
/// its raw platform label, and [SoundRecognition.start] takes a `rawLabels`
/// filter.
enum CanonicalSound {
  // Animals
  /// Heard as "dog".
  dog(SoundCategory.animals, 'dog'),

  /// Heard as "cat".
  cat(SoundCategory.animals, 'cat'),

  /// Heard as "bird".
  bird(SoundCategory.animals, 'bird'),

  /// Heard as "chicken".
  chicken(SoundCategory.animals, 'chicken'),

  /// Heard as "duck".
  duck(SoundCategory.animals, 'duck'),

  /// Heard as "cow".
  cow(SoundCategory.animals, 'cow'),

  /// Heard as "pig".
  pig(SoundCategory.animals, 'pig'),

  /// Heard as "sheep".
  sheep(SoundCategory.animals, 'sheep'),

  /// Heard as "horse".
  horse(SoundCategory.animals, 'horse'),

  /// Heard as "buzzing insect".
  insectBuzz(SoundCategory.animals, 'buzzing insect'),

  // People
  /// Heard as "talking".
  speech(SoundCategory.people, 'talking'),

  /// Heard as "laughing".
  laughter(SoundCategory.people, 'laughing'),

  /// Heard as "crying".
  crying(SoundCategory.people, 'crying'),

  /// Heard as "singing".
  singing(SoundCategory.people, 'singing'),

  /// Heard as "whistling".
  whistling(SoundCategory.people, 'whistling'),

  /// Heard as "shouting".
  shouting(SoundCategory.people, 'shouting'),

  /// Heard as "whispering".
  whispering(SoundCategory.people, 'whispering'),

  /// Heard as "clapping".
  clapping(SoundCategory.people, 'clapping'),

  /// Heard as "finger snap".
  fingerSnapping(SoundCategory.people, 'finger snap'),

  /// Heard as "cough".
  cough(SoundCategory.people, 'cough'),

  /// Heard as "sneeze".
  sneeze(SoundCategory.people, 'sneeze'),

  /// Heard as "snoring".
  snoring(SoundCategory.people, 'snoring'),

  /// Heard as "burp".
  burp(SoundCategory.people, 'burp'),

  /// Heard as "chewing".
  chewing(SoundCategory.people, 'chewing'),

  /// Heard as "footsteps".
  footsteps(SoundCategory.people, 'footsteps'),

  // Home
  /// Heard as "doorbell".
  doorbell(SoundCategory.home, 'doorbell'),

  /// Heard as "knocking".
  knock(SoundCategory.home, 'knocking'),

  /// Heard as "door slam".
  doorSlam(SoundCategory.home, 'door slam'),

  /// Heard as "phone ringing".
  telephone(SoundCategory.home, 'phone ringing'),

  /// Heard as "alarm clock".
  alarmClock(SoundCategory.home, 'alarm clock'),

  /// Heard as "ticking clock".
  clockTick(SoundCategory.home, 'ticking clock'),

  /// Heard as "beep".
  beep(SoundCategory.home, 'beep'),

  /// Heard as "running water".
  waterTap(SoundCategory.home, 'running water'),

  /// Heard as "toilet flush".
  toiletFlush(SoundCategory.home, 'toilet flush'),

  /// Heard as "vacuum cleaner".
  vacuumCleaner(SoundCategory.home, 'vacuum cleaner'),

  /// Heard as "microwave".
  microwave(SoundCategory.home, 'microwave'),

  /// Heard as "blender".
  blender(SoundCategory.home, 'blender'),

  /// Heard as "hair dryer".
  hairDryer(SoundCategory.home, 'hair dryer'),

  /// Heard as "toothbrush".
  toothbrush(SoundCategory.home, 'toothbrush'),

  /// Heard as "dishes".
  dishes(SoundCategory.home, 'dishes'),

  /// Heard as "typing".
  typing(SoundCategory.home, 'typing'),

  /// Heard as "jangling keys".
  keysJangling(SoundCategory.home, 'jangling keys'),

  /// Heard as "zipper".
  zipper(SoundCategory.home, 'zipper'),

  /// Heard as "scissors".
  scissors(SoundCategory.home, 'scissors'),

  /// Heard as "crumpling paper".
  crumpling(SoundCategory.home, 'crumpling paper'),

  // Music
  /// Heard as "music".
  music(SoundCategory.music, 'music'),

  /// Heard as "piano".
  piano(SoundCategory.music, 'piano'),

  /// Heard as "guitar".
  guitar(SoundCategory.music, 'guitar'),

  /// Heard as "drum".
  drum(SoundCategory.music, 'drum'),

  /// Heard as "bell".
  bell(SoundCategory.music, 'bell'),

  /// Heard as "xylophone".
  xylophone(SoundCategory.music, 'xylophone'),

  /// Heard as "tambourine".
  tambourine(SoundCategory.music, 'tambourine'),

  // Outdoors
  /// Heard as "siren".
  siren(SoundCategory.outdoors, 'siren'),

  /// Heard as "car horn".
  carHorn(SoundCategory.outdoors, 'car horn'),

  /// Heard as "car engine".
  car(SoundCategory.outdoors, 'car engine'),

  /// Heard as "airplane".
  airplane(SoundCategory.outdoors, 'airplane'),

  /// Heard as "rain".
  rain(SoundCategory.outdoors, 'rain'),

  /// Heard as "thunder".
  thunder(SoundCategory.outdoors, 'thunder'),

  /// Heard as "wind".
  wind(SoundCategory.outdoors, 'wind'),

  /// Heard as "bouncing ball".
  bouncingBall(SoundCategory.outdoors, 'bouncing ball');

  const CanonicalSound(this.category, this.displayName);

  /// The group this sound is listed under.
  final SoundCategory category;

  /// A short English noun phrase — "phone ringing", "jangling keys" — for a
  /// debug screen or a first cut of the UI.
  ///
  /// Not localised: a shipped game should
  /// key its own strings off [name].
  final String displayName;
}
