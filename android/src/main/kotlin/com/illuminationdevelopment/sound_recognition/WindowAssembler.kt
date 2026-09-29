package com.illuminationdevelopment.sound_recognition

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
  val hop: Int = maxOf(1, (windowSize * (1 - overlap)).toInt())
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

  /** Forgets partial audio — after a gap, the old half-window is not adjacent to the new one. */
  fun reset() {
    filled = 0
  }
}
