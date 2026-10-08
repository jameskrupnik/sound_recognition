package com.jameskrupnik.sound_recognition

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The pause/resume bookkeeping between the main thread (activity lifecycle)
 * and the capture thread.
 */
class CaptureGateTest {
  @Test fun aSegmentOpenedBeforeAPauseIsDeadEvenAfterAQuickResume() {
    // The bug: a boolean `paused` went true and back to false (stop then
    // start of the activity) before the capture loop looked at it, and the
    // loop carried on reading an AudioRecord that pause() had stopped.
    val gate = CaptureGate()
    val segment = gate.open { it }!!
    assertTrue(gate.isLive(segment))
    gate.pause {}
    gate.resume()
    assertFalse(gate.isLive(segment))
    assertTrue(gate.isLive(gate.open { it }!!))
  }

  @Test fun nothingOpensWhilePaused() {
    val gate = CaptureGate()
    gate.pause {}
    assertTrue(gate.isPaused)
    assertNull(gate.open { "opened" })
    gate.resume()
    assertEquals("opened", gate.open { "opened" })
  }

  @Test fun pauseIsIdempotentAndRunsItsActionOnce() {
    val gate = CaptureGate()
    var runs = 0
    assertTrue(gate.pause { runs++ })
    assertFalse(gate.pause { runs++ })
    assertEquals(1, runs)
  }

  @Test fun aPauseWaitsForAnOpeningToFinish() {
    // So "listening", posted while opening, cannot land after the pause's
    // "interrupted" and leave the state reading listening while paused.
    val gate = CaptureGate()
    val events = mutableListOf<String>()
    val inside = CountDownLatch(1)
    val release = CountDownLatch(1)
    val opener = Thread {
      gate.open {
        inside.countDown()
        release.await(2, TimeUnit.SECONDS)
        synchronized(events) { events.add("listening") }
      }
    }.apply { start() }
    assertTrue(inside.await(2, TimeUnit.SECONDS))
    val pauser = Thread { gate.pause { synchronized(events) { events.add("interrupted") } } }.apply { start() }
    Thread.sleep(50)
    release.countDown()
    opener.join(2_000)
    pauser.join(2_000)
    assertEquals(listOf("listening", "interrupted"), events)
  }
}
