package dev.apissystems.flutter_card_scanner_plus

import android.content.Context
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.util.Size
import android.view.OrientationEventListener
import android.view.Surface
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.UseCase
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import io.flutter.view.TextureRegistry
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Owns the CameraX session: a Preview use case rendered into a Flutter
 * texture and an ImageAnalysis use case feeding ML Kit. Frames never leave
 * the device and are never written to disk.
 */
class CameraSession(
    private val context: Context,
    textures: TextureRegistry,
    private val onFrame: (Map<String, Any>) -> Unit,
) : LifecycleOwner {

    class PreviewInfo(val textureId: Long, val width: Int, val height: Int, val rotation: Int)

    /** Normalized, top-left origin, upright coordinates. `null` = whole frame. */
    @Volatile
    var regionOfInterest: RectF? = null

    /** Called when a device rotation changes the shape of the preview. */
    var onPreviewChanged: ((PreviewInfo) -> Unit)? = null

    /** Called when the camera fails after it started. */
    var onError: ((String, String) -> Unit)? = null

    private val registry = LifecycleRegistry(this)
    override val lifecycle: Lifecycle get() = registry

    private val producer: TextureRegistry.SurfaceProducer = textures.createSurfaceProducer()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mainExecutor = Executor { mainHandler.post(it) }
    private val analysisExecutor = Executors.newSingleThreadExecutor()

    private var provider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var preview: Preview? = null
    private var analysis: ImageAnalysis? = null
    private var onReady: ((PreviewInfo) -> Unit)? = null
    private var lastInfo: PreviewInfo? = null
    private var orientationListener: OrientationEventListener? = null
    private val busy = AtomicBoolean(false)
    private var lastRun = 0L

    init {
        registry.currentState = Lifecycle.State.CREATED
    }

    fun start(onReady: (PreviewInfo) -> Unit) {
        this.onReady = onReady
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            val provider = future.get()
            this.provider = provider
            bind(provider)
        }, mainExecutor)
    }

    private fun bind(provider: ProcessCameraProvider) {
        val resolution = ResolutionSelector.Builder()
            .setAspectRatioStrategy(AspectRatioStrategy.RATIO_16_9_FALLBACK_AUTO_STRATEGY)
            .setResolutionStrategy(
                ResolutionStrategy(Size(1920, 1080), ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER)
            )
            .build()

        val preview = Preview.Builder().setResolutionSelector(resolution).build()
        preview.setSurfaceProvider(mainExecutor, ::provideSurface)
        this.preview = preview

        val analysis = ImageAnalysis.Builder()
            .setResolutionSelector(resolution)
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()
        this.analysis = analysis
        analysis.setAnalyzer(analysisExecutor) { proxy ->
            val now = System.currentTimeMillis()
            if (busy.get() || now - lastRun < MIN_INTERVAL_MS) {
                proxy.close()
                return@setAnalyzer
            }
            busy.set(true)
            lastRun = now
            TextRecognizer.process(proxy, regionOfInterest) { frame ->
                busy.set(false)
                mainHandler.post { onFrame(frame) }
            }
        }

        registry.currentState = Lifecycle.State.STARTED
        // Bind to this session's own lifecycle and nothing else: the provider
        // is process wide, and unbinding everything on it would tear down a
        // session that another part of the app is still using.
        val camera = provider.bindToLifecycle(
            this, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis,
        )
        this.camera = camera
        observeState(camera)
        startOrientationUpdates(preview, analysis)

        // Surface can be dropped while backgrounded (Impeller); re-request on return.
        producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
            override fun onSurfaceAvailable() {
                this@CameraSession.preview?.setSurfaceProvider(mainExecutor, ::provideSurface)
            }

            override fun onSurfaceCleanup() {}
        })
    }

    private fun provideSurface(request: androidx.camera.core.SurfaceRequest) {
        val size = request.resolution
        producer.setSize(size.width, size.height)
        request.provideSurface(producer.surface, mainExecutor) { }
        // The listener stays attached: CameraX reports a new transform on
        // every rotation, which is what keeps the preview upright.
        request.setTransformationInfoListener(mainExecutor) { info ->
            val rotation = info.rotationDegrees
            val upright = if (rotation == 90 || rotation == 270) {
                size.height to size.width
            } else {
                size.width to size.height
            }
            val next = PreviewInfo(producer.id(), upright.first, upright.second, rotation)
            val ready = onReady
            if (ready != null) {
                onReady = null
                lastInfo = next
                ready(next)
                return@setTransformationInfoListener
            }
            val previous = lastInfo
            if (previous == null ||
                previous.rotation != next.rotation ||
                previous.width != next.width ||
                previous.height != next.height
            ) {
                lastInfo = next
                onPreviewChanged?.invoke(next)
            }
        }
    }

    /**
     * Follows device rotation so both use cases target the current display.
     * ImageAnalysis matters most: ML Kit reads rotationDegrees off the frame,
     * and a stale target leaves it reading sideways text.
     */
    private fun startOrientationUpdates(preview: Preview, analysis: ImageAnalysis) {
        orientationListener?.disable()
        val listener = object : OrientationEventListener(context) {
            override fun onOrientationChanged(orientation: Int) {
                if (orientation == ORIENTATION_UNKNOWN) return
                val rotation = when {
                    orientation >= 315 || orientation < 45 -> Surface.ROTATION_0
                    orientation < 135 -> Surface.ROTATION_270
                    orientation < 225 -> Surface.ROTATION_180
                    else -> Surface.ROTATION_90
                }
                if (rotation == preview.targetRotation) return
                preview.targetRotation = rotation
                analysis.targetRotation = rotation
            }
        }
        orientationListener = listener
        if (listener.canDetectOrientation()) listener.enable()
    }

    fun setTorch(enabled: Boolean) {
        camera?.cameraControl?.enableTorch(enabled)
    }

    /**
     * Releases everything and then calls [onDone], on the main thread.
     *
     * The callback is what lets the Dart side await a stop: starting a new
     * session while the previous teardown was still queued was leaving the
     * preview black on reopen.
     */
    fun stop(onDone: () -> Unit) {
        orientationListener?.disable()
        orientationListener = null
        onPreviewChanged = null
        onError = null

        val teardown = Runnable {
            registry.currentState = Lifecycle.State.DESTROYED
            val cases = listOfNotNull<UseCase>(preview, analysis)
            if (cases.isNotEmpty()) provider?.unbind(*cases.toTypedArray())
            provider = null
            camera = null
            preview = null
            analysis = null
            producer.release()
            analysisExecutor.shutdown()
            onDone()
        }

        if (Looper.myLooper() == Looper.getMainLooper()) teardown.run()
        else mainHandler.post(teardown)
    }

    /**
     * Reports a camera that fails after it started: another app took it, the
     * device ran out of resources, or it was disabled by policy. Without this
     * the preview simply froze.
     */
    private fun observeState(camera: Camera) {
        camera.cameraInfo.cameraState.observe(this) { state ->
            val error = state.error ?: return@observe
            onError?.invoke("cameraError", "CameraX reported error ${error.code}")
        }
    }

    private companion object {
        /** ML Kit needs ~50–120 ms per frame on mid-range devices; ~8 fps is enough. */
        const val MIN_INTERVAL_MS = 120L
    }
}
