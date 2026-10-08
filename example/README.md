# sound_recognition example

Two tabs:

- **Live** — every label that clears a 0.3 floor, newest first, with its
  canonical sound (or "(not canonical)"), raw platform label, confidence and
  time since that Listen began (each Listen starts a fresh list and a fresh
  clock). **Save audio** also records the session through `recordTo` and
  says where the file went: on Android the app's external files directory,
  so `adb pull /sdcard/Android/data/com.jameskrupnik.sound_recognition_example/files/live.m4a`
  fetches it; on iOS, the app's Documents directory.
- **Hunt** — one canonical sound to find, listened for with
  `start(sounds: {target})`, and "Found it!" on the first detection. This is
  the shape of the scavenger-hunt game the package was written for.

```console
$ flutter run
```

iOS needs a device or simulator on iOS 15+, and the simulator listens through
the Mac's microphone. The Android emulator only hears the host microphone when
*Extended controls → Microphone → "Virtual microphone uses host audio input"*
is on.
