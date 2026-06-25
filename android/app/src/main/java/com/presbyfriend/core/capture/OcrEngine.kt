package com.presbyfriend.core.capture

import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions

/**
 * Off-screen OCR engine backed by ML Kit Chinese text recognizer.
 * Processes a bitmap and returns recognized text blocks with position info.
 */
object OcrEngine {

    private val recognizer = TextRecognition.getClient(
        ChineseTextRecognizerOptions.Builder().build()
    )

    /**
     * Recognize text from a bitmap, returning blocks positioned by their
     * top Y coordinate as a fraction of image height (0.0 = top, 1.0 = bottom).
     *
     * Call from [kotlinx.coroutines.Dispatchers.Default] to avoid blocking main thread.
     */
    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    suspend fun recognize(bitmap: Bitmap): List<PositionedBlock> {
        return kotlinx.coroutines.suspendCancellableCoroutine { continuation ->
            val image = InputImage.fromBitmap(bitmap, 0)
            recognizer.process(image)
                .addOnSuccessListener { visionText ->
                    val blocks = visionText.textBlocks.mapNotNull { block ->
                        val text = block.text.trim()
                        if (text.isBlank()) return@mapNotNull null
                        val topYRatio = block.boundingBox?.let { box ->
                            (box.top.toFloat() / bitmap.height).coerceIn(0f, 1f)
                        } ?: 0f
                        PositionedBlock(text = text, topYRatio = topYRatio)
                    }
                    continuation.resume(blocks, null)
                }
                .addOnFailureListener {
                    continuation.resume(emptyList(), null)
                }
        }
    }
}
