package dev.apissystems.flutter_card_scanner_plus

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry

/**
 * Method channel: `flutter_card_scanner_plus/methods`
 *   start(regionOfInterest?: Box) -> {textureId, previewWidth, previewHeight, rotation}
 *   stop()
 *   setTorch(enabled: Boolean)
 *   setRegionOfInterest(Box)
 *   recognizeImage(bytes: ByteArray, regionOfInterest?: Box) -> {lines}
 * Event channel: `flutter_card_scanner_plus/frames`
 *   {lines: [{text, box: {left, top, width, height}, confidence}]}
 *
 * All boxes are normalized (0..1) in upright (portrait) preview coordinates
 * with a top-left origin. `rotation` is the clockwise rotation, in degrees,
 * the Dart side must apply to the texture to display it upright.
 */
class FlutterCardScannerPlusPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var textures: TextureRegistry

    private var activityBinding: ActivityPluginBinding? = null
    private var session: CameraSession? = null
    private var eventSink: EventChannel.EventSink? = null
    private var pendingStart: (() -> Unit)? = null
    private var pendingStartResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val activity: Activity? get() = activityBinding?.activity

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        textures = binding.textureRegistry
        methods = MethodChannel(binding.binaryMessenger, "flutter_card_scanner_plus/methods")
        methods.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "flutter_card_scanner_plus/frames")
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stop()
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    // region ActivityAware

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        stop()
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
    }

    // endregion

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call.argument<Map<String, Any>>("regionOfInterest"), result)
            "stop" -> {
                stop()
                result.success(null)
            }
            "setTorch" -> {
                session?.setTorch(call.argument<Boolean>("enabled") ?: false)
                result.success(null)
            }
            "setRegionOfInterest" -> {
                session?.regionOfInterest = parseBox(call.arguments as? Map<*, *>)
                result.success(null)
            }
            "recognizeImage" -> {
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes == null) {
                    result.error("invalidArgument", "bytes missing", null)
                    return
                }
                val roi = parseBox(call.argument<Map<String, Any>>("regionOfInterest"))
                TextRecognizer.recognizeImage(bytes, roi) { frame ->
                    mainHandler.post {
                        if (frame != null) result.success(frame)
                        else result.error("invalidImage", "Could not decode image", null)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun start(roiArg: Map<String, Any>?, result: MethodChannel.Result) {
        val activity = activity
        if (activity == null) {
            result.error("noActivity", "Plugin is not attached to an Activity", null)
            return
        }
        if (session != null) {
            result.error("alreadyRunning", "Scanner is already running", null)
            return
        }
        val roi = parseBox(roiArg)

        val launch = {
            try {
                val s = CameraSession(activity, textures) { frame -> eventSink?.success(frame) }
                s.regionOfInterest = roi
                session = s
                s.start { info ->
                    result.success(
                        mapOf(
                            "textureId" to info.textureId,
                            "previewWidth" to info.width,
                            "previewHeight" to info.height,
                            "rotation" to info.rotation,
                        )
                    )
                }
            } catch (e: Exception) {
                session = null
                result.error("cameraError", e.message, null)
            }
        }

        if (activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            launch()
        } else {
            pendingStart = launch
            pendingStartResult = result
            activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), PERMISSION_REQUEST)
        }
    }

    private fun stop() {
        session?.stop()
        session = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val launch = pendingStart
        val result = pendingStartResult
        pendingStart = null
        pendingStartResult = null
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            launch?.invoke()
        } else {
            result?.error("permissionDenied", "Camera permission denied", null)
        }
        return true
    }

    // region EventChannel.StreamHandler

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // endregion

    private fun parseBox(map: Map<*, *>?): RectF? {
        if (map == null) return null
        val left = (map["left"] as? Number)?.toFloat() ?: return null
        val top = (map["top"] as? Number)?.toFloat() ?: return null
        val width = (map["width"] as? Number)?.toFloat() ?: return null
        val height = (map["height"] as? Number)?.toFloat() ?: return null
        return RectF(left, top, left + width, top + height)
    }

    private companion object {
        const val PERMISSION_REQUEST = 0x4CA7
    }
}
