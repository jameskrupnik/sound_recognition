package com.jameskrupnik.sound_recognition

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.util.Log
import java.io.File
import java.nio.ByteOrder
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Mono PCM16 in, an AAC-LC `.m4a` out: `MediaCodec` to `MediaMuxer`.
 *
 * Fed from the capture loop the classifier already runs, never from a second
 * `AudioRecord` — there is one microphone. [write] copies the chunk and hands
 * it to a thread of its own, so encoding never holds up classification.
 *
 * Best effort by design: every failure is logged and ends the recording, and
 * none reaches the caller, because a broken recording must not stop the
 * listening it rides on. A file is only left behind if at least one encoded
 * frame was muxed and the muxer stopped cleanly; otherwise it is deleted, so a
 * file that exists is a playable file.
 */
internal class AacRecorder private constructor(
  private val path: String,
  private val sampleRate: Int,
  private val codec: MediaCodec,
  private val muxer: MediaMuxer,
) {
  private val executor: ExecutorService =
    Executors.newSingleThreadExecutor { Thread(it, "sound_recognition.recording") }
  private val finished = AtomicBoolean(false)

  // Everything below is touched only on the executor's thread.
  private val info = MediaCodec.BufferInfo()
  private var track = -1
  private var muxing = false
  private var closed = false
  private var failed = false
  private var samplesIn = 0L
  private var framesOut = 0

  /** Queues [n] samples of [pcm] for encoding. The array may be reused at once. */
  fun write(pcm: ShortArray, n: Int) {
    if (n <= 0 || finished.get()) return
    val copy = pcm.copyOf(n)
    try {
      executor.execute { encode(copy) }
    } catch (_: RejectedExecutionException) {
      // Finished between the check and the hand-off: the chunk is dropped.
    }
  }

  /** Ends the recording and finalizes the file, without waiting. Idempotent. */
  fun finish() {
    if (!finished.compareAndSet(false, true)) return
    try {
      executor.execute(::finalizeFile)
    } catch (_: RejectedExecutionException) {
    }
    executor.shutdown()
  }

  /** [finish], then waits up to [timeoutMs] for the file to be finalized. */
  fun finishAndWait(timeoutMs: Long): Boolean {
    finish()
    return try {
      executor.awaitTermination(timeoutMs, TimeUnit.MILLISECONDS)
    } catch (_: InterruptedException) {
      Thread.currentThread().interrupt()
      false
    }
  }

  private fun encode(samples: ShortArray) {
    if (closed || failed) return
    try {
      var offset = 0
      var stalls = 0
      while (offset < samples.size) {
        val index = codec.dequeueInputBuffer(TIMEOUT_US)
        if (index < 0) {
          // The encoder is full: take its output and try again, but not
          // forever — a wedged codec must not grow the queue without bound.
          if (++stalls > MAX_STALLS) throw IllegalStateException("AAC encoder stopped taking input")
          drain(endOfStream = false)
          continue
        }
        stalls = 0
        val buffer = codec.getInputBuffer(index) ?: throw IllegalStateException("no input buffer")
        buffer.clear()
        val count = minOf(samples.size - offset, buffer.remaining() / 2)
        buffer.order(ByteOrder.nativeOrder()).asShortBuffer().put(samples, offset, count)
        codec.queueInputBuffer(index, 0, count * 2, presentationUs(), 0)
        samplesIn += count
        offset += count
        drain(endOfStream = false)
      }
    } catch (e: Exception) {
      Log.w(TAG, "Recording to $path failed; keeping what was encoded", e)
      failed = true
      finish()
    }
  }

  private fun presentationUs() = samplesIn * 1_000_000L / sampleRate

  /**
   * Moves encoded frames to the muxer. Without [endOfStream] it takes only
   * what is ready; with it, it waits for the end-of-stream frame, within a
   * bound.
   */
  private fun drain(endOfStream: Boolean) {
    var waits = 0
    while (true) {
      val index = codec.dequeueOutputBuffer(info, if (endOfStream) TIMEOUT_US else 0)
      when {
        index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
          if (!endOfStream || ++waits > MAX_STALLS) return
        }
        index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
          // Arrives once, before the first frame, carrying the codec config
          // the muxer needs; the muxer cannot start any earlier than this.
          if (!muxing) {
            track = muxer.addTrack(codec.outputFormat)
            muxer.start()
            muxing = true
          }
        }
        index >= 0 -> {
          val out = codec.getOutputBuffer(index)
          val config = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
          if (out != null && !config && info.size > 0 && muxing) {
            out.position(info.offset)
            out.limit(info.offset + info.size)
            muxer.writeSampleData(track, out, info)
            framesOut++
          }
          codec.releaseOutputBuffer(index, false)
          if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
        }
      }
    }
  }

  private fun finalizeFile() {
    closed = true
    if (!failed && samplesIn > 0) {
      try {
        var index = -1
        var tries = 0
        while (index < 0 && tries++ < MAX_STALLS) {
          index = codec.dequeueInputBuffer(TIMEOUT_US)
          if (index < 0) drain(endOfStream = false)
        }
        if (index >= 0) {
          codec.queueInputBuffer(index, 0, 0, presentationUs(), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
          drain(endOfStream = true)
        }
      } catch (e: Exception) {
        Log.w(TAG, "Recording to $path: draining the encoder failed", e)
      }
    }
    runCatching { codec.stop() }
    runCatching { codec.release() }
    // MediaMuxer.stop() throws if it never started or holds no samples, and
    // the file it leaves then is not an m4a. Delete it rather than hand the
    // app something that will not play.
    var playable = false
    if (muxing && framesOut > 0) {
      playable = runCatching { muxer.stop() }
        .onFailure { Log.w(TAG, "Recording to $path could not be finalized", it) }
        .isSuccess
    }
    runCatching { muxer.release() }
    if (!playable) {
      File(path).delete()
      if (samplesIn == 0L) Log.i(TAG, "No audio arrived for $path; no file written")
    }
  }

  companion object {
    private const val TAG = "sound_recognition"
    private const val TIMEOUT_US = 10_000L
    private const val MAX_STALLS = 200 // 2 s at TIMEOUT_US
    const val BIT_RATE = 64_000

    /**
     * Opens an encoder and a muxer writing to [path], replacing any file
     * there. Returns null, having logged why, if either cannot be created —
     * a missing directory, a read-only path, no AAC encoder.
     */
    fun open(path: String, sampleRate: Int): AacRecorder? {
      var codec: MediaCodec? = null
      var muxer: MediaMuxer? = null
      return try {
        // MediaMuxer opens without truncating, so a longer old file would
        // keep its tail. Start from nothing.
        File(path).delete()
        muxer = MediaMuxer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, 1).apply {
          setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
          setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE)
          setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16 * 1024)
        }
        codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()
        AacRecorder(path, sampleRate, codec, muxer)
      } catch (e: Exception) {
        Log.w(TAG, "Not recording to $path; classification continues without it", e)
        runCatching { codec?.release() }
        runCatching { muxer?.release() }
        File(path).delete()
        null
      }
    }
  }
}
