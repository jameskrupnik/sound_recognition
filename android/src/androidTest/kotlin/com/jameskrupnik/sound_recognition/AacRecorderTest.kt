package com.jameskrupnik.sound_recognition

import android.media.MediaExtractor
import android.media.MediaFormat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Runs [AacRecorder] on the device's real AAC encoder and muxer, fed the way
 * [MicrophoneListener] feeds it: 100 ms chunks of 16 kHz PCM16, from one of
 * the clips in `tool/test_audio`. The file it writes is then opened with
 * `MediaExtractor` to prove it is an m4a of the right length, not just bytes.
 *
 * Like [YamnetClassifierTest], it does not cover `AudioRecord` itself.
 */
@RunWith(AndroidJUnit4::class)
class AacRecorderTest {
  private val dir = InstrumentationRegistry.getInstrumentation().targetContext.cacheDir

  private fun feed(recorder: AacRecorder, pcm: ShortArray) {
    val chunk = ShortArray(YamnetClassifier.SAMPLE_RATE / 10)
    var i = 0
    while (i < pcm.size) {
      val n = minOf(chunk.size, pcm.size - i)
      System.arraycopy(pcm, i, chunk, 0, n)
      recorder.write(chunk, n) // the loop reuses chunk at once, as capture does
      i += n
    }
  }

  @Test fun writesAPlayableMonoAacM4a() {
    val file = File(dir, "speech.m4a").apply { delete() }
    val pcm = TestAudio.readWav("speech.wav")
    val recorder = AacRecorder.open(file.path, YamnetClassifier.SAMPLE_RATE)
    assertNotNull(recorder)
    feed(recorder!!, pcm)
    assertTrue("finalized in time", recorder.finishAndWait(5_000))

    assertTrue("file exists", file.exists())
    assertTrue("file is not empty", file.length() > 0)
    val extractor = MediaExtractor()
    try {
      extractor.setDataSource(file.path)
      assertEquals(1, extractor.trackCount)
      val format = extractor.getTrackFormat(0)
      assertEquals(MediaFormat.MIMETYPE_AUDIO_AAC, format.getString(MediaFormat.KEY_MIME))
      assertEquals(1, format.getInteger(MediaFormat.KEY_CHANNEL_COUNT))
      assertEquals(YamnetClassifier.SAMPLE_RATE, format.getInteger(MediaFormat.KEY_SAMPLE_RATE))
      val expectedUs = pcm.size * 1_000_000L / YamnetClassifier.SAMPLE_RATE
      val durationUs = format.getLong(MediaFormat.KEY_DURATION)
      println("sound_recognition speech.m4a: ${file.length()} bytes, ${durationUs / 1000} ms of ${expectedUs / 1000} ms")
      assertTrue("duration $durationUs vs $expectedUs", kotlin.math.abs(durationUs - expectedUs) < 200_000)
    } finally {
      extractor.release()
      file.delete()
    }
  }

  @Test fun noAudioLeavesNoFile() {
    val file = File(dir, "empty.m4a")
    file.writeText("an old file at the same path")
    val recorder = AacRecorder.open(file.path, YamnetClassifier.SAMPLE_RATE)
    assertNotNull(recorder)
    assertTrue(recorder!!.finishAndWait(5_000))
    assertFalse("no file for no audio", file.exists())
  }

  @Test fun writesAfterFinishAreDroppedAndFinishIsIdempotent() {
    val file = File(dir, "late.m4a").apply { delete() }
    val recorder = AacRecorder.open(file.path, YamnetClassifier.SAMPLE_RATE)!!
    feed(recorder, TestAudio.readWav("sine.wav"))
    recorder.finish()
    recorder.write(ShortArray(1600), 1600)
    recorder.finish()
    assertTrue(recorder.finishAndWait(5_000))
    assertTrue(file.exists() && file.length() > 0)
    file.delete()
  }

  @Test fun anUnwritablePathReturnsNull() {
    assertNull(AacRecorder.open(File(dir, "no/such/dir/a.m4a").path, YamnetClassifier.SAMPLE_RATE))
  }
}
