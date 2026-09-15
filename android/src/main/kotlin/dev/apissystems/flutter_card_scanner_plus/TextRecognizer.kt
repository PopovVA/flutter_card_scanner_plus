package dev.apissystems.flutter_card_scanner_plus

import android.graphics.BitmapFactory
import android.graphics.RectF
import androidx.camera.core.ImageProxy
import androidx.exifinterface.media.ExifInterface
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.io.ByteArrayInputStream

/** Runs ML Kit text recognition and converts results to the channel's line format. */
object TextRecognizer {
    private val client by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }

    /**
     * Recognizes text in a camera frame. Always closes [proxy] when done.
     * Boxes are normalized to the upright frame; [roi] (normalized, upright)
     * filters lines whose center lies outside it.
     */
    @androidx.annotation.OptIn(androidx.camera.core.ExperimentalGetImage::class)
    fun process(proxy: ImageProxy, roi: RectF?, callback: (Map<String, Any>) -> Unit) {
        val media = proxy.image
        if (media == null) {
            proxy.close()
            return
        }
        val rotation = proxy.imageInfo.rotationDegrees
        val (width, height) = uprightSize(proxy.width, proxy.height, rotation)
        val input = InputImage.fromMediaImage(media, rotation)
        client.process(input)
            .addOnSuccessListener { text -> callback(mapOf("lines" to toLines(text, width, height, roi))) }
            .addOnCompleteListener { proxy.close() }
    }

    /** One-shot recognition of an encoded image (JPEG/PNG/WebP…), honouring EXIF orientation. */
    fun recognizeImage(bytes: ByteArray, roi: RectF?, callback: (Map<String, Any>?) -> Unit) {
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        if (bitmap == null) {
            callback(null)
            return
        }
        val rotation = try {
            when (ExifInterface(ByteArrayInputStream(bytes)).getAttributeInt(
                ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL,
            )) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90
                ExifInterface.ORIENTATION_ROTATE_180 -> 180
                ExifInterface.ORIENTATION_ROTATE_270 -> 270
                else -> 0
            }
        } catch (_: Exception) {
            0
        }
        val (width, height) = uprightSize(bitmap.width, bitmap.height, rotation)
        client.process(InputImage.fromBitmap(bitmap, rotation))
            .addOnSuccessListener { text -> callback(mapOf("lines" to toLines(text, width, height, roi))) }
            .addOnFailureListener { callback(mapOf("lines" to emptyList<Any>())) }
    }

    private fun uprightSize(width: Int, height: Int, rotation: Int): Pair<Int, Int> =
        if (rotation == 90 || rotation == 270) height to width else width to height

    private fun toLines(text: Text, width: Int, height: Int, roi: RectF?): List<Map<String, Any>> {
        val lines = ArrayList<Map<String, Any>>()
        for (block in text.textBlocks) {
            for (line in block.lines) {
                val box = line.boundingBox ?: continue
                val left = box.left.toDouble() / width
                val top = box.top.toDouble() / height
                val w = box.width().toDouble() / width
                val h = box.height().toDouble() / height
                if (roi != null && !roi.contains((left + w / 2).toFloat(), (top + h / 2).toFloat())) continue
                lines.add(
                    mapOf(
                        "text" to line.text,
                        "confidence" to line.confidence.toDouble(),
                        "box" to mapOf("left" to left, "top" to top, "width" to w, "height" to h),
                    )
                )
            }
        }
        return lines
    }
}
