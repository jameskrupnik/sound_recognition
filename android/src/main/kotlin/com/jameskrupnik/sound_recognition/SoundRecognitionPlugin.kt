package com.jameskrupnik.sound_recognition

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * The Android half: a method channel for permission and metadata, and an
 * event channel whose listen/cancel *is* start/stop.
 *
 * Tying the microphone's lifetime to the event channel subscription means
 * there is no state in which Dart has stopped listening and the microphone is
 * still on — cancelling the Dart stream is enough. A hot restart does *not*
 * cancel channel streams (the new isolate just listens again), so the engine's
 * pre-restart hook stops the microphone explicitly.
 */
class SoundRecognitionPlugin :
  FlutterPlugin,
  MethodChannel.MethodCallHandler,
  EventChannel.StreamHandler,
  ActivityAware,
  PluginRegistry.RequestPermissionsResultListener {

  private lateinit var context: Context
  private lateinit var methods: MethodChannel
  private lateinit var events: EventChannel

  private var binding: ActivityPluginBinding? = null
  private var pendingPermission: MethodChannel.Result? = null
  private var listener: MicrophoneListener? = null
  private var engine: FlutterEngine? = null

  // One background thread that starts each listener only after the one it
  // replaced has exited, so the main thread never waits for a capture thread
  // and two AudioRecords are never open at once.
  private var lifecycleExecutor: ExecutorService? = null
  private val main = Handler(Looper.getMainLooper())

  // Hot restart replaces the Dart isolate without cancelling the event
  // channel, so without this the AudioRecord outlives the Dart code that owned
  // it until the next start().
  private val engineLifecycle = object : FlutterEngine.EngineLifecycleListener {
    override fun onPreEngineRestart() = stopListening()
    override fun onEngineWillDestroy() = Unit
  }

  override fun onAttachedToEngine(flutter: FlutterPlugin.FlutterPluginBinding) {
    context = flutter.applicationContext
    lifecycleExecutor = Executors.newSingleThreadExecutor { Thread(it, "sound_recognition_lifecycle") }
    engine = flutter.flutterEngine.also { it.addEngineLifecycleListener(engineLifecycle) }
    methods = MethodChannel(flutter.binaryMessenger, "sound_recognition")
    methods.setMethodCallHandler(this)
    events = EventChannel(flutter.binaryMessenger, "sound_recognition/events")
    events.setStreamHandler(this)
  }

  override fun onDetachedFromEngine(flutter: FlutterPlugin.FlutterPluginBinding) {
    methods.setMethodCallHandler(null)
    events.setStreamHandler(null)
    engine?.removeEngineLifecycleListener(engineLifecycle)
    engine = null
    stopListening()
    // Lets the queued wait for the last listener run, then ends the thread.
    lifecycleExecutor?.shutdown()
    lifecycleExecutor = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      // minSdk 24 is the whole requirement; there is no device this plugin
      // installs on that cannot run the model.
      "isSupported" -> result.success(true)
      "permissionStatus" -> result.success(permissionStatus())
      "requestPermission" -> requestPermission(result)
      "awaitIdle" -> awaitIdle(result)
      "knownLabels" -> try {
        result.success(YamnetClassifier.readLabels(context.assets))
      } catch (e: Exception) {
        result.error("MODEL_UNAVAILABLE", e.message, null)
      }
      else -> result.notImplemented()
    }
  }

  // --- Listening -----------------------------------------------------------

  override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
    stopListening()
    if (!hasPermission()) {
      events.error("PERMISSION_DENIED", "RECORD_AUDIO is not granted", null)
      return
    }
    val args = arguments as? Map<*, *> ?: emptyMap<String, Any>()
    // Each listener talks only to the sink it was started for, and only while
    // it is still the current listener. Anything an old listener had already
    // queued on the main thread when it was replaced is dropped here rather
    // than delivered into the new session.
    lateinit var created: MicrophoneListener
    fun current() = listener === created
    created = MicrophoneListener(
      context,
      minConfidence = (args["minConfidence"] as? Number)?.toDouble() ?: 0.5,
      overlap = (args["overlap"] as? Number)?.toDouble() ?: 0.5,
      recordTo = args["recordTo"] as? String,
      callbacks = object : MicrophoneListener.Callbacks {
        override fun onResult(timeMs: Long, labels: List<String>, confidences: List<Double>) {
          if (!current()) return
          events.success(
            mapOf(
              "event" to "result",
              "classifier" to "yamnet",
              "timeMs" to timeMs,
              "labels" to labels,
              "confidences" to confidences,
            ),
          )
        }

        override fun onState(state: MicrophoneListener.State) {
          if (!current()) return
          events.success(mapOf("event" to "state", "state" to state.name.lowercase()))
        }

        override fun onError(code: String, message: String) {
          if (!current()) return
          events.error(code, message, null)
          stopListening()
        }
      },
    )
    listener = created
    inBackground(created::start)
  }

  override fun onCancel(arguments: Any?) = stopListening()

  private fun stopListening() {
    val stopping = listener ?: return
    // Cleared first: callbacks the stop itself triggers are no longer current.
    listener = null
    stopping.stop()
    // Finalizing a recording can take up to FINALIZE_MS; a little more covers
    // releasing the AudioRecord. Past that, the next start goes ahead anyway.
    inBackground { stopping.awaitExit(MicrophoneListener.FINALIZE_MS + EXIT_SLACK_MS) }
  }

  /**
   * Replies once every stop queued so far has finished, recording included,
   * so Dart's stop() completes with the file ready. Never blocks the main
   * thread.
   */
  private fun awaitIdle(result: MethodChannel.Result) {
    val executor = lifecycleExecutor ?: return result.success(null)
    try {
      executor.execute { main.post { result.success(null) } }
    } catch (_: RejectedExecutionException) {
      result.success(null)
    }
  }

  /** Queues [block] behind earlier starts and stops; dropped after detach. */
  private fun inBackground(block: () -> Unit) {
    try {
      lifecycleExecutor?.execute(block)
    } catch (_: RejectedExecutionException) {
    }
  }

  // --- Permission ----------------------------------------------------------

  private fun hasPermission() =
    ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
      PackageManager.PERMISSION_GRANTED

  /**
   * Android cannot say "never asked" apart from "denied for good" — both
   * have `shouldShowRequestPermissionRationale` false. So does a prompt the
   * user dismissed with Back, which Android will show again. What separates
   * "denied for good" from both is that the rationale flag was true once (the
   * user denied a prompt) and has gone false since (they denied it again, or
   * ticked "don't ask again"). The rationale flag is sampled on every status
   * check and every request result, and remembered in a private preference.
   */
  private fun permissionStatus(): String {
    if (hasPermission()) return "granted"
    val activity = binding?.activity
    val mayAskAgain = activity?.shouldShowRequestPermissionRationale(Manifest.permission.RECORD_AUDIO) ?: false
    if (mayAskAgain) {
      prefs().edit().putBoolean(DENIED_ONCE_KEY, true).apply()
      return "undetermined"
    }
    return if (prefs().getBoolean(DENIED_ONCE_KEY, false)) "denied" else "undetermined"
  }

  private fun requestPermission(result: MethodChannel.Result) {
    val activity = binding?.activity
    if (hasPermission() || activity == null || pendingPermission != null) {
      result.success(permissionStatus())
      return
    }
    pendingPermission = result
    activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_CODE)
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray,
  ): Boolean {
    if (requestCode != REQUEST_CODE) return false
    pendingPermission?.success(permissionStatus())
    pendingPermission = null
    return true
  }

  private fun prefs() = context.getSharedPreferences("sound_recognition", Context.MODE_PRIVATE)

  // --- Activity lifecycle --------------------------------------------------

  /**
   * Pauses capture while the app's activity is not visible. A backgrounded
   * app is silenced by Android 9+ anyway; releasing the `AudioRecord` also
   * frees the mic for whatever the user switched to. Resumes on return.
   */
  private val lifecycle = object : Application.ActivityLifecycleCallbacks {
    override fun onActivityStarted(activity: Activity) {
      if (activity === binding?.activity) listener?.resume()
    }

    override fun onActivityStopped(activity: Activity) {
      if (activity === binding?.activity) listener?.pause()
    }

    override fun onActivityCreated(activity: Activity, state: Bundle?) = Unit
    override fun onActivityResumed(activity: Activity) = Unit
    override fun onActivityPaused(activity: Activity) = Unit
    override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) = Unit
    override fun onActivityDestroyed(activity: Activity) = Unit
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    this.binding = binding
    binding.addRequestPermissionsResultListener(this)
    binding.activity.application.registerActivityLifecycleCallbacks(lifecycle)
  }

  override fun onDetachedFromActivity() {
    binding?.removeRequestPermissionsResultListener(this)
    binding?.activity?.application?.unregisterActivityLifecycleCallbacks(lifecycle)
    binding = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
    onAttachedToActivity(binding)

  override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

  private companion object {
    const val REQUEST_CODE = 0x534e // "SN"
    const val DENIED_ONCE_KEY = "microphone_denied_once"
    const val EXIT_SLACK_MS = 1_000L
  }
}
