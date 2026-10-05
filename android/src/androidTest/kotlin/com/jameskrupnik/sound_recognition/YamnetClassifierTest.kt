package com.jameskrupnik.sound_recognition

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.AfterClass
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Runs the shipped model through the shipped Kotlin — [YamnetClassifier] and
 * [WindowAssembler], exactly as [MicrophoneListener] drives them — on the
 * clips in `tool/test_audio`, on a device or emulator.
 *
 *   cd example/android && ./gradlew :sound_recognition:connectedDebugAndroidTest
 *
 * What it does not cover is `AudioRecord` itself: the samples come from a
 * WAV, not a microphone.
 */
@RunWith(AndroidJUnit4::class)
class YamnetClassifierTest {
  companion object {
    private lateinit var classifier: YamnetClassifier

    @BeforeClass @JvmStatic fun load() {
      classifier = YamnetClassifier(InstrumentationRegistry.getInstrumentation().context.assets)
    }

    @AfterClass @JvmStatic fun close() = classifier.close()
  }

  /** The best score each label reached over the clip, 50% overlap. */
  private fun bestScores(clip: String): Map<String, Float> {
    val pcm = TestAudio.readWav(clip)
    val best = FloatArray(classifier.labels.size)
    var windows = 0
    val assembler = WindowAssembler(YamnetClassifier.WINDOW_SAMPLES, 0.5) { window, _ ->
      windows++
      val scores = classifier.classify(window)
      for (i in scores.indices) best[i] = maxOf(best[i], scores[i])
    }
    // Pushed in 100 ms chunks, the size the capture loop reads.
    var i = 0
    while (i < pcm.size) {
      val n = minOf(1600, pcm.size - i)
      assembler.push(pcm.copyOfRange(i, i + n), n)
      i += n
    }
    assertTrue("no full window in $clip", windows > 0)
    val top = classifier.labels.indices.sortedByDescending { best[it] }.take(4)
    println("sound_recognition $clip -> " + top.joinToString(" | ") { "${classifier.labels[it]} ${"%.2f".format(best[it])}" })
    return classifier.labels.indices.associate { classifier.labels[it] to best[it] }
  }

  private fun top(scores: Map<String, Float>) = scores.maxByOrNull { it.value }!!.key

  @Test fun labelListMatchesModelOutput() {
    assertEquals(521, classifier.labels.size)
    assertEquals("Speech", classifier.labels.first())
  }

  @Test fun speechIsSpeech() = assertEquals("Speech", top(bestScores("speech.wav")))

  @Test fun sirenIsSiren() = assertTrue(bestScores("siren.wav").getValue("Siren") > 0.5f)

  @Test fun telephoneIsTelephone() =
    assertTrue(bestScores("telephone.wav").getValue("Telephone") > 0.5f)

  @Test fun whistleIsWhistle() = assertEquals("Whistle", top(bestScores("whistle.wav")))

  @Test fun sineIsABeep() = assertEquals("Beep, bleep", top(bestScores("sine.wav")))

  @Test fun windowsAdvanceByTheHop() {
    val starts = mutableListOf<Long>()
    val assembler = WindowAssembler(100, 0.5) { _, start -> starts.add(start) }
    assembler.push(ShortArray(260), 260)
    assertEquals(listOf(0L, 50L, 100L, 150L), starts)
  }
}
