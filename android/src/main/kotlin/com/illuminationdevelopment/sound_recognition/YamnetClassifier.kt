package com.illuminationdevelopment.sound_recognition

import android.content.res.AssetManager
import java.io.Closeable
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.tensorflow.lite.Interpreter

/**
 * YAMNet, run directly on LiteRT's `Interpreter`.
 *
 * ### Why not MediaPipe Tasks' `AudioClassifier`
 *
 * It is the documented way to run this exact model, and it was the plan. It
 * was dropped for one reason: **MediaPipe Tasks reports usage metrics to
 * Google.** Its privacy notice says so in terms ("MediaPipe Tasks APIs send
 * metrics about the performance and utilization of the APIs in your app to
 * Google"), and `tasks-core` pulls in `transport-backend-cct` to do it. The
 * first consumer of this package is a children's game whose promise is that
 * nothing leaves the phone and no network is used; a classifier that phones
 * home breaks the second half of that and has to be disclosed in the Play
 * Data safety form besides.
 *
 * LiteRT (`com.google.ai.edge.litert:litert`, the renamed TensorFlow Lite)
 * has no dependencies at all and no telemetry, and what MediaPipe added on top
 * of it for this model is small: YAMNet takes raw 16 kHz mono float samples —
 * the log-mel front end is *inside* the graph — and returns 521 sigmoid scores.
 * The only thing left to write is the windowing, in [WindowAssembler].
 *
 * It is also smaller: MediaPipe's `tasks-core` 1.0.0 alone is a 22.5 MB AAR;
 * LiteRT 1.4.2 is 8.3 MB for four ABIs, of which an app bundle delivers one
 * (4.5 MB uncompressed on arm64).
 */
internal class YamnetClassifier(assets: AssetManager) : Closeable {
  val labels: List<String> = readLabels(assets)
  private val interpreter: Interpreter
  private val output = Array(1) { FloatArray(labels.size) }

  init {
    // Read into a direct buffer rather than memory-mapping the asset. Mapping
    // needs the asset stored uncompressed, which a *library* cannot guarantee:
    // `noCompress` in this module's build does not reach the consuming app's
    // packaging. A 4 MB copy on the capture thread is the price of not
    // depending on every consumer's build.gradle.
    val bytes = assets.open(MODEL_ASSET).use { it.readBytes() }
    val model = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder())
    model.put(bytes).rewind()
    interpreter = Interpreter(model, Interpreter.Options().setNumThreads(2))
    check(interpreter.getOutputTensor(0).shape().last() == labels.size) {
      "Model has ${interpreter.getOutputTensor(0).shape().last()} classes, " +
        "label list has ${labels.size}"
    }
  }

  /** Scores for one window of exactly [WINDOW_SAMPLES] samples in [-1, 1]. */
  fun classify(window: FloatArray): FloatArray {
    require(window.size == WINDOW_SAMPLES) { "Need $WINDOW_SAMPLES samples, got ${window.size}" }
    interpreter.run(window, output)
    return output[0].copyOf()
  }

  override fun close() = interpreter.close()

  companion object {
    const val SAMPLE_RATE = 16_000

    /** 0.975 s at 16 kHz: YAMNet's fixed input, and the iOS window to match. */
    const val WINDOW_SAMPLES = 15_600

    const val MODEL_ASSET = "sound_recognition/yamnet.tflite"
    const val LABELS_ASSET = "sound_recognition/yamnet_labels.txt"

    fun readLabels(assets: AssetManager): List<String> =
      assets.open(LABELS_ASSET).bufferedReader().use { r ->
        r.readLines().filter { it.isNotEmpty() }
      }
  }
}
