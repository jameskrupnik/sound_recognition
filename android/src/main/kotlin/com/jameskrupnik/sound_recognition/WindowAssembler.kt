package com.jameskrupnik.sound_recognition

import kotlin.math.roundToInt

/**
 * Cuts a stream of samples into overlapping fixed-size windows.
 *
 * `AudioRecord` hands back whatever it has — 100 ms here, 40 ms there — and
 * the model wants exactly [windowSize] samples every [hop]. This holds the
 * last window's worth and calls back each time another hop has arrived.
 *
 * Separate from the capture loop so the instrumented test can drive the very
 * same code from a WAV file instead of a microphone.
 */
internal class WindowAssembler(
  private val windowSize: Int,
  overlap: Double,
  private val onWindow: (window: FloatArray, startSample: Long) -> Unit,
) {
  // Rounded, not truncated: 1 - 0.8 is 0.19999… in binary, and truncating
  // made the hop a sample short at 0.8 and 0.9.
  val hop: Int = maxOf(1, (windowSize * (1 - overlap)).roundToInt())
  private val buffer = FloatArray(windowSize)
  private var filled = 0
  private var consumed = 0L

  /** Appends [count] 16-bit samples from [pcm], emitting any windows completed. */
  fun push(pcm: ShortArray, count: Int) {
    var i = 0
    while (i < count) {
      val take = minOf(count - i, windowSize - filled)
      for (k in 0 until take) buffer[filled + k] = pcm[i + k] / 32768f
      filled += take
      i += take
      if (filled == windowSize) {
        onWindow(buffer.copyOf(), consumed)
        // Keep the tail as the head of the next window.
        System.arraycopy(buffer, hop, buffer, 0, windowSize - hop)
        filled = windowSize - hop
        consumed += hop
      }
    }
  }

  /**
   * Accounts for [count] samples that were captured but must not be
   * classified (the microphone was silenced), and forgets the partial window:
   * audio from before the gap is not adjacent to audio after it. The next
   * window starts at the first sample pushed afterwards, and its start
   * position still counts the skipped samples, so timestamps stay true.
   */
  fun skip(count: Int) {
    consumed += filled + count
    filled = 0
  }
}
