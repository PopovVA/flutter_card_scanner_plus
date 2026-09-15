package dev.apissystems.flutter_card_scanner_plus

import android.content.Context
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.util.Size
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
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

    private val registry = LifecycleRegistry(this)
    override val lifecycle: Lifecycle get() = registry

    private val producer: TextureRegistry.SurfaceProducer = textures.createSurfaceProducer()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mainExecutor = Executor { mainHandler.post(it) }
    private val analysisExecutor = Executors.newSingleThreadExecutor()

    private var provider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var preview: Preview? = null
    private var onReady: ((PreviewInfo) -> Unit)? = null
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
        provider.unbindAll()
        camera = provider.bindToLifecycle(this, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)

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
        request.setTransformationInfoListener(mainExecutor) { info ->
            val ready = onReady ?: return@setTransformationInfoListener
            onReady = null
            val rotation = info.rotationDegrees
            val upright = if (rotation == 90 || rotation == 270) size.height to size.width else size.width to size.height
            ready(PreviewInfo(producer.id(), upright.first, upright.second, rotation))
        }
    }

    fun setTorch(enabled: Boolean) {
        camera?.cameraControl?.enableTorch(enabled)
    }

    fun stop() {
        mainHandler.post {
            registry.currentState = Lifecycle.State.DESTROYED
            provider?.unbindAll()
            provider = null
            camera = null
            preview = null
            producer.release()
            analysisExecutor.shutdown()
        }
    }

    private companion object {
        /** ML Kit needs ~50–120 ms per frame on mid-range devices; ~8 fps is enough. */
        const val MIN_INTERVAL_MS = 120L
    }
}
