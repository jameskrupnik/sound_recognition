package com.jameskrupnik.sound_recognition

/**
 * Pause and resume, as the main thread sees them, against the capture
 * thread's segments.
 *
 * A boolean `paused` was not enough. The activity can stop and start again
 * (pause, resume) before the capture loop next looks, and the loop would then
 * carry on reading the `AudioRecord` that [pause] had just stopped — getting
 * nothing, forever, while the state said `interrupted`. So each pause also
 * ends the *segment* that was open: a segment is live only while no pause has
 * happened since it opened.
 *
 * [open] and [pause] run their actions under one lock, so the "listening" an
 * opening posts and the "interrupted" a pause posts reach the main thread in
 * the order they happened.
 */
internal class CaptureGate {
  private val lock = Any()
  @Volatile private var paused = false
  @Volatile private var generation = 0

  val isPaused: Boolean get() = paused

  /**
   * Runs [action] — stopping the recorder, ending the recording, reporting
   * the interruption — and ends the open segment. False, without running it,
   * if already paused.
   */
  fun pause(action: () -> Unit): Boolean = synchronized(lock) {
    if (paused) return false
    paused = true
    generation++
    action()
    true
  }

  fun resume() {
    synchronized(lock) { paused = false }
  }

  /**
   * Opens a segment unless paused, running [start] with its token while no
   * pause can intervene. Null if paused.
   */
  fun <T> open(start: (segment: Int) -> T): T? = synchronized(lock) {
    if (paused) null else start(generation)
  }

  /** Whether [segment] may keep capturing: no pause since it opened. */
  fun isLive(segment: Int): Boolean = !paused && generation == segment
}
