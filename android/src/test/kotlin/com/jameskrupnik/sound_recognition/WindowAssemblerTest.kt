package com.jameskrupnik.sound_recognition

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

/** The windowing the capture loop and the instrumented test both use, on the JVM. */
class WindowAssemblerTest {
  private class Recorded {
    val starts = mutableListOf<Long>()
    val windows = mutableListOf<FloatArray>()
  }

  private fun assembler(size: Int, overlap: Double, into: Recorded) =
    WindowAssembler(size, overlap) { window, start ->
      into.starts.add(start)
      into.windows.add(window)
    }

  private fun ramp(from: Int, count: Int) = ShortArray(count) { (from + it).toShort() }

  @Test fun windowsAdvanceByTheHop() {
    val r = Recorded()
    assembler(100, 0.5, r).push(ShortArray(260), 260)
    assertEquals(listOf(0L, 50L, 100L, 150L), r.starts)
  }

  @Test fun theHopIsExactForEveryOverlapStartAccepts() {
    // 1 - 0.8 and 1 - 0.9 are just under 0.2 and 0.1 in binary, so a
    // truncating conversion made the hop one sample short — and every
    // timestamp drifted by a sample per window.
    for ((overlap, hop) in listOf(0.0 to 15_600, 0.5 to 7_800, 0.7 to 4_680, 0.8 to 3_120, 0.9 to 1_560)) {
      assertEquals("overlap $overlap", hop, WindowAssembler(YamnetClassifier.WINDOW_SAMPLES, overlap) { _, _ -> }.hop)
    }
  }

  @Test fun windowsCarryTheRightSamplesAcrossUnevenChunks() {
    val r = Recorded()
    val a = assembler(4, 0.5, r)
    a.push(ramp(0, 3), 3)
    a.push(ramp(3, 5), 5) // 3..7
    assertEquals(listOf(0L, 2L, 4L), r.starts)
    assertArrayEquals(floatArrayOf(4f, 5f, 6f, 7f).map { it / 32768f }.toFloatArray(), r.windows[2], 0f)
  }

  @Test fun eachWindowIsItsOwnArray() {
    val r = Recorded()
    assembler(4, 0.5, r).push(ramp(0, 8), 8)
    assertEquals(0f, r.windows[0][0], 0f)
    assertEquals(2f / 32768f, r.windows[1][0], 0f)
  }

  @Test fun skipDropsThePartialWindowAndKeepsTheClock() {
    val r = Recorded()
    val a = assembler(4, 0.5, r)
    a.push(ramp(0, 5), 5) // window at 0; samples 2..4 held
    a.skip(10) // samples 5..14 never arrive (silenced)
    a.push(ramp(15, 4), 4)
    assertEquals(listOf(0L, 15L), r.starts)
    // Nothing from before the gap is in the window after it.
    assertArrayEquals(floatArrayOf(15f, 16f, 17f, 18f).map { it / 32768f }.toFloatArray(), r.windows[1], 0f)
  }

  @Test fun pushHonoursCountNotTheArrayLength() {
    val r = Recorded()
    val a = assembler(4, 0.0, r)
    a.push(ramp(0, 10), 3)
    a.push(ramp(100, 10), 1)
    assertArrayEquals(floatArrayOf(0f, 1f, 2f, 100f).map { it / 32768f }.toFloatArray(), r.windows.single(), 0f)
  }
}
