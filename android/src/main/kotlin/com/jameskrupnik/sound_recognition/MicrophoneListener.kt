package com.jameskrupnik.sound_recognition

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioRecordingConfiguration
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Microphone to YAMNet to callbacks, on one background thread.
 *
 * ### Interruptions
 *
 * Android does not *stop* an app's recording when something else wants the
 * microphone; since Android 10 it **silences** it — `read` keeps returning,
 * full of zeros. Classifying that would report a stream of "Silence", so the
 * listener asks [AudioManager]'s recording callback whether this client is
 * silenced (API 29+) and reports [State.INTERRUPTED] instead of results.
 *
 * Going to the background is handled by the plugin calling [pause] and
 * [resume] from the activity lifecycle, because Android 9+ silences
 * background capture anyway and a paused `AudioRecord` releases the mic for
 * whatever the user switched to.
 *
 * ### Recording
 *
 * With [recordTo], the same PCM chunks the classifier reads are also handed to
 * an [AacRecorder]. There is no second `AudioRecord`. The recording ends at the
 * first interruption of any kind (pause, silencing, a failed start or read)
 * and when listening stops: an m4a cannot be appended to, and finalizing at
 * the interruption means a process killed in the background still leaves a
 * playable file. Classification carries on either way.
 *
 * ### Threads
 *
 * [start], [stop], [pause] and [resume] never block, so the main thread can
 * call them. Waiting for the capture thread to finish (it may be closing the
 * `AudioRecord` or finalizing the recording) is [awaitExit], for a background
 * thread; the plugin runs the next [start] after it, so two `AudioRecord`s are
 * never open at once.
 *
 * ### Timestamps
 *
 * A result's time is when its window began, in milliseconds since *this*
 * listener was created — that is, since this `start()` began listening, so
 * each `start()` counts from zero again. Within one capture segment it is
 * audio time (samples read); a new segment after an interruption starts from
 * the wall-clock time since listening began, so times keep rising across an
 * interruption and include the time spent interrupted. iOS follows the same
 * rule.
 */
internal class MicrophoneListener(
  private val context: Context,
  private val minConfidence: Double,
  private val overlap: Double,
  private val recordTo: String?,
  private val callbacks: Callbacks,
) {
  enum class State { LISTENING, INTERRUPTED }

  interface Callbacks {
    fun onResult(timeMs: Long, labels: List<String>, confidences: List<Double>)
    fun onState(state: State)
    fun onError(code: String, message: String)
  }

  private val main = Handler(Looper.getMainLooper())
  private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
  private val startedAt = SystemClock.elapsedRealtime()

  @Volatile private var running = true
  // Counted down by stop(), so the capture thread's waits end at once.
  private val stopSignal = CountDownLatch(1)
  private val threadLock = Any()
  @Volatile private var silenced = false
  @Volatile private var record: AudioRecord? = null
  private val gate = CaptureGate()
  private var thread: Thread? = null
  private val recordingCallback = AtomicReference<AudioManager.AudioRecordingCallback?>(null)

  // The recording, and whether it has ended; [recordingLock] keeps an end that
  // races the opening (a pause while the model loads) from being lost.
  private val recordingLock = Any()
  private var recorder: AacRecorder? = null
  private var recordingOver = false

  /** Starts the capture thread, unless [stop] came first. */
  fun start() {
    synchronized(threadLock) {
      if (!running) return
      thread = Thread(::run, "sound_recognition").also { it.start() }
    }
  }

  /** Tells the capture thread to finish, without waiting for it. */
  fun stop() {
    synchronized(threadLock) { running = false }
    stopSignal.countDown()
    record?.let { runCatching { it.stop() } }
    unregisterSilenceCallback()
  }

  /**
   * Waits, off the main thread, for the capture thread to release the
   * `AudioRecord` and finalize the recording. False if it outlived [timeoutMs].
   */
  fun awaitExit(timeoutMs: Long): Boolean {
    val exiting = synchronized(threadLock) { thread } ?: return true
    exiting.join(timeoutMs)
    return !exiting.isAlive
  }

  fun pause() {
    gate.pause {
      record?.let { runCatching { it.stop() } }
      endRecording()
      post { callbacks.onState(State.INTERRUPTED) }
    }
  }

  fun resume() = gate.resume()

  private fun run() {
    val classifier = try {
      YamnetClassifier(context.assets)
    } catch (e: Exception) {
      post { callbacks.onError("MODEL_UNAVAILABLE", e.message ?: e.toString()) }
      return
    }
    openRecording()
    try {
      classifier.use {
        while (running) {
          if (gate.isPaused) {
            pauseFor(100)
            continue
          }
          if (!captureSegment(it)) return
        }
      }
    } finally {
      // Covers stop(), start() replacing this listener, and fatal errors.
      synchronized(recordingLock) {
        recordingOver = true
        recorder
      }?.finishAndWait(FINALIZE_MS)
    }
  }

  /**
   * Opened here, off the main thread, because it touches the file system. A
   * null recorder just means no recording; AacRecorder logged why. Not opened
   * at all if an interruption already ended the recording while the model
   * loaded.
   */
  private fun openRecording() {
    val path = recordTo ?: return
    val opened = AacRecorder.open(path, YamnetClassifier.SAMPLE_RATE) ?: return
    val keep = synchronized(recordingLock) {
      if (!recordingOver) recorder = opened
      !recordingOver
    }
    // Finished with nothing written, which deletes the empty file.
    if (!keep) opened.finish()
  }

  /** Finalizes the recording, if any, without waiting. Safe from any thread. */
  private fun endRecording() {
    synchronized(recordingLock) {
      recordingOver = true
      recorder
    }?.finish()
  }

  private fun writeRecording(pcm: ShortArray, n: Int) {
    // AacRecorder.write drops chunks once finished, so no lock is needed.
    recorder?.write(pcm, n)
  }

  /**
   * One uninterrupted stretch of recording, from starting an `AudioRecord` to
   * pausing or stopping. Returns false after reporting a fatal error.
   *
   * Timestamps are wall time since listening began at the segment's start,
   * plus audio time within it — so they keep increasing across a pause rather
   * than restarting at zero, and match what the iOS side reports.
   */
  @SuppressLint("MissingPermission") // Checked by the plugin before start.
  private fun captureSegment(classifier: YamnetClassifier): Boolean {
    val rec = openRecord() ?: run {
      post { callbacks.onError("AUDIO_UNAVAILABLE", "AudioRecord could not be initialised at 16 kHz mono") }
      return false
    }
    try {
      // Opened under the gate, so a pause cannot land between starting the
      // recorder and reporting LISTENING, and "listening" cannot arrive after
      // that pause's "interrupted".
      val segment = gate.open { token ->
        record = rec
        registerSilenceCallback(rec)
        rec.startRecording()
        val recording = rec.recordingState == AudioRecord.RECORDSTATE_RECORDING
        if (recording) post { callbacks.onState(State.LISTENING) }
        token to recording
      } ?: return true // paused while opening: the outer loop waits
      val (token, recording) = segment
      if (!recording) {
        // Before Android 10 only one app can capture at a time, and
        // startRecording() fails *without throwing* while another holds the
        // mic (a call, a voice assistant). Reporting LISTENING here would be
        // a lie that never recovers; report an interruption and retry.
        endRecording()
        post { callbacks.onState(State.INTERRUPTED) }
        pauseFor(RETRY_MS)
        return true
      }
      val segmentStartMs = SystemClock.elapsedRealtime() - startedAt
      val assembler = WindowAssembler(YamnetClassifier.WINDOW_SAMPLES, overlap) { window, startSample ->
        if (!silenced) report(classifier, window, segmentStartMs + startSample * 1000 / YamnetClassifier.SAMPLE_RATE)
      }
      val chunk = ShortArray(YamnetClassifier.SAMPLE_RATE / 10)
      while (running && gate.isLive(token)) {
        val n = rec.read(chunk, 0, chunk.size)
        if (n < 0) {
          // ERROR_DEAD_OBJECT and friends: the audio server went away under
          // us. Returning true lets the outer loop open a fresh AudioRecord,
          // after a pause so a persistent failure is not a busy loop.
          // (A read cut short by stop() or pause() is not a failure.)
          if (running && gate.isLive(token)) {
            endRecording()
            post { callbacks.onState(State.INTERRUPTED) }
            pauseFor(RETRY_MS)
          }
          break
        }
        if (silenced) {
          // Silenced audio is zeros. Recording it is pointless (silencing
          // ended the recording anyway), and classifying windows that are
          // part zeros after the silencing lifts would report "Silence" and
          // dilute whatever is really there; keep the clock, drop the audio.
          assembler.skip(n)
          continue
        }
        writeRecording(chunk, n)
        assembler.push(chunk, n)
      }
    } catch (e: IllegalStateException) {
      post { callbacks.onError("AUDIO_UNAVAILABLE", e.message ?: "startRecording failed") }
      return false
    } finally {
      unregisterSilenceCallback()
      runCatching { rec.stop() }
      rec.release()
      record = null
    }
    return true
  }

  private fun report(classifier: YamnetClassifier, window: FloatArray, timeMs: Long) {
    val scores = classifier.classify(window)
    val labels = ArrayList<String>()
    val confidences = ArrayList<Double>()
    for (i in scores.indices) {
      if (scores[i] >= minConfidence) {
        labels.add(classifier.labels[i])
        confidences.add(scores[i].toDouble())
      }
    }
    if (labels.isEmpty()) return
    post { callbacks.onResult(timeMs, labels, confidences) }
  }

  @SuppressLint("MissingPermission")
  private fun openRecord(): AudioRecord? {
    val minBuffer = AudioRecord.getMinBufferSize(
      YamnetClassifier.SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
    )
    if (minBuffer <= 0) return null
    // VOICE_RECOGNITION rather than MIC: the CDD asks devices to turn off
    // noise suppression and automatic gain control for this source, and
    // noise suppression is built to delete precisely the non-speech sounds
    // this package is listening for.
    val rec = AudioRecord(
      MediaRecorder.AudioSource.VOICE_RECOGNITION,
      YamnetClassifier.SAMPLE_RATE,
      AudioFormat.CHANNEL_IN_MONO,
      AudioFormat.ENCODING_PCM_16BIT,
      maxOf(minBuffer, YamnetClassifier.SAMPLE_RATE), // at least 0.5 s of PCM16
    )
    if (rec.state != AudioRecord.STATE_INITIALIZED) {
      rec.release()
      return null
    }
    return rec
  }

  private fun registerSilenceCallback(rec: AudioRecord) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
    val session = rec.audioSessionId
    val callback = object : AudioManager.AudioRecordingCallback() {
      override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>) {
        // A change already queued on the main thread when this callback was
        // unregistered still arrives. Ignore it rather than report a stale
        // state into whatever session is current by then.
        if (!running || recordingCallback.get() !== this) return
        val mine = configs.firstOrNull { it.clientAudioSessionId == session } ?: return
        val nowSilenced = mine.isClientSilenced
        if (nowSilenced == silenced) return
        silenced = nowSilenced
        if (nowSilenced) endRecording()
        callbacks.onState(if (nowSilenced) State.INTERRUPTED else State.LISTENING)
      }
    }
    recordingCallback.set(callback)
    audioManager.registerAudioRecordingCallback(callback, main)
  }

  /** From the capture thread at a segment's end, and from [stop]; once only. */
  private fun unregisterSilenceCallback() {
    val callback = recordingCallback.getAndSet(null) ?: return
    audioManager.unregisterAudioRecordingCallback(callback)
    silenced = false
  }

  /** Waits [ms] on the capture thread, or less if [stop] is called. */
  private fun pauseFor(ms: Long) {
    stopSignal.await(ms, TimeUnit.MILLISECONDS)
  }

  private fun post(block: () -> Unit) {
    main.post { if (running) block() }
  }

  companion object {
    private const val RETRY_MS = 1_000L

    /** How long the capture thread gives the recording to be finalized. */
    const val FINALIZE_MS = 2_000L
  }
}
