package com.illuminationdevelopment.sound_recognition

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
  @Volatile private var paused = false
  @Volatile private var silenced = false
  @Volatile private var record: AudioRecord? = null
  @Volatile private var recorder: AacRecorder? = null
  private var thread: Thread? = null
  private var recordingCallback: AudioManager.AudioRecordingCallback? = null

  fun start() {
    thread = Thread(::run, "sound_recognition").also { it.start() }
  }

  fun stop() {
    running = false
    record?.let { runCatching { it.stop() } }
    thread?.join(1_000)
    thread = null
    unregisterSilenceCallback()
  }

  fun pause() {
    if (paused) return
    paused = true
    record?.let { runCatching { it.stop() } }
    endRecording()
    post { callbacks.onState(State.INTERRUPTED) }
  }

  fun resume() {
    paused = false
  }

  private fun run() {
    val classifier = try {
      YamnetClassifier(context.assets)
    } catch (e: Exception) {
      post { callbacks.onError("MODEL_UNAVAILABLE", e.message ?: e.toString()) }
      return
    }
    // Opened here, off the main thread, because it touches the file system.
    // A null recorder just means no recording; AacRecorder logged why.
    recorder = recordTo?.let { AacRecorder.open(it, YamnetClassifier.SAMPLE_RATE) }
    try {
      classifier.use {
        while (running) {
          if (paused) {
            Thread.sleep(100)
            continue
          }
          if (!captureSegment(it)) return
        }
      }
    } finally {
      // Covers stop(), start() replacing this listener, and fatal errors.
      recorder?.finishAndWait(FINALIZE_MS)
    }
  }

  /** Finalizes the recording, if any, without waiting. Safe from any thread. */
  private fun endRecording() {
    recorder?.finish()
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
    record = rec
    registerSilenceCallback(rec)
    val segmentStartMs = SystemClock.elapsedRealtime() - startedAt
    val assembler = WindowAssembler(YamnetClassifier.WINDOW_SAMPLES, overlap) { window, startSample ->
      if (!silenced) report(classifier, window, segmentStartMs + startSample * 1000 / YamnetClassifier.SAMPLE_RATE)
    }
    try {
      rec.startRecording()
      if (rec.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
        // Before Android 10 only one app can capture at a time, and
        // startRecording() fails *without throwing* while another holds the
        // mic (a call, a voice assistant). Reporting LISTENING here would be
        // a lie that never recovers; report an interruption and retry.
        endRecording()
        post { callbacks.onState(State.INTERRUPTED) }
        Thread.sleep(RETRY_MS)
        return true
      }
      post { callbacks.onState(State.LISTENING) }
      val chunk = ShortArray(YamnetClassifier.SAMPLE_RATE / 10)
      while (running && !paused) {
        val n = rec.read(chunk, 0, chunk.size)
        if (n < 0) {
          // ERROR_DEAD_OBJECT and friends: the audio server went away under
          // us. Returning true lets the outer loop open a fresh AudioRecord,
          // after a pause so a persistent failure is not a busy loop.
          // (A read cut short by stop() or pause() is not a failure.)
          if (running && !paused) {
            endRecording()
            post { callbacks.onState(State.INTERRUPTED) }
            Thread.sleep(RETRY_MS)
          }
          break
        }
        // Silenced audio is zeros, and silencing ends the recording anyway.
        if (!silenced) recorder?.write(chunk, n)
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
        val mine = configs.firstOrNull { it.clientAudioSessionId == session } ?: return
        val nowSilenced = mine.isClientSilenced
        if (nowSilenced == silenced) return
        silenced = nowSilenced
        if (nowSilenced) endRecording()
        callbacks.onState(if (nowSilenced) State.INTERRUPTED else State.LISTENING)
      }
    }
    recordingCallback = callback
    audioManager.registerAudioRecordingCallback(callback, main)
  }

  private fun unregisterSilenceCallback() {
    val callback = recordingCallback ?: return
    recordingCallback = null
    audioManager.unregisterAudioRecordingCallback(callback)
    silenced = false
  }

  private fun post(block: () -> Unit) {
    main.post { if (running) block() }
  }

  private companion object {
    const val RETRY_MS = 1_000L
    const val FINALIZE_MS = 2_000L
  }
}
