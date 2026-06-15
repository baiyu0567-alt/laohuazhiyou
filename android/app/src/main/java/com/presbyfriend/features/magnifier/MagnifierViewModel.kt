package com.presbyfriend.features.magnifier

import android.Manifest
import android.app.Application
import android.content.pm.PackageManager
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ProcessLifecycleOwner
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.Executors

class MagnifierViewModel(application: Application) : AndroidViewModel(application) {

    private val _zoomLevel = MutableStateFlow(1.0f)
    val zoomLevel: StateFlow<Float> = _zoomLevel.asStateFlow()

    private val _torchEnabled = MutableStateFlow(false)
    val torchEnabled: StateFlow<Boolean> = _torchEnabled.asStateFlow()

    private val _detectedTexts = MutableStateFlow<List<String>>(emptyList())
    val detectedTexts: StateFlow<List<String>> = _detectedTexts.asStateFlow()

    private val _hasPermission = MutableStateFlow(false)
    val hasPermission: StateFlow<Boolean> = _hasPermission.asStateFlow()

    private var camera: androidx.camera.core.Camera? = null
    private var imageAnalysis: ImageAnalysis? = null
    private val analyzerExecutor = Executors.newSingleThreadExecutor()
    private val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

    fun checkPermission() {
        val ctx = getApplication<Application>()
        _hasPermission.value = ContextCompat.checkSelfPermission(ctx, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
    }

    fun startCamera(previewView: PreviewView) {
        val ctx = getApplication<Application>()
        val cameraProviderFuture = ProcessCameraProvider.getInstance(ctx)

        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()

            val preview = Preview.Builder().build().also {
                it.setSurfaceProvider(previewView.surfaceProvider)
            }

            imageAnalysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .build()
                .also { analysis ->
                    analysis.setAnalyzer(analyzerExecutor) { imageProxy ->
                        recognizeText(imageProxy)
                    }
                }

            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

            cameraProvider.unbindAll()
            camera = cameraProvider.bindToLifecycle(
                lifecycleOwner = ProcessLifecycleOwner.get(),
                cameraSelector,
                preview,
                imageAnalysis
            ).also { boundCamera ->
                camera = boundCamera
            }
        }, ContextCompat.getMainExecutor(ctx))
    }

    fun setZoom(level: Float) {
        _zoomLevel.value = level.coerceIn(1.0f, 8.0f)
        camera?.cameraControl?.setLinearZoom(_zoomLevel.value / 8.0f)
    }

    fun toggleTorch() {
        _torchEnabled.value = !_torchEnabled.value
        camera?.cameraControl?.enableTorch(_torchEnabled.value)
    }

    private fun recognizeText(imageProxy: ImageProxy) {
        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close()
            return
        }

        val image = InputImage.fromMediaImage(mediaImage, imageProxy.imageInfo.rotationDegrees)
        recognizer.process(image)
            .addOnSuccessListener { visionText ->
                val blocks = visionText.textBlocks.map { it.text }
                _detectedTexts.value = blocks
            }
            .addOnCompleteListener {
                imageProxy.close()
            }
    }

    override fun onCleared() {
        super.onCleared()
        analyzerExecutor.shutdown()
    }
}
