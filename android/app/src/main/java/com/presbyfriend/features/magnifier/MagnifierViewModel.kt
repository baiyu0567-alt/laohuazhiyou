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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class MagnifierViewModel(application: Application) : AndroidViewModel(application) {

    private val _zoomLevel = MutableStateFlow(1.0f)
    val zoomLevel: StateFlow<Float> = _zoomLevel.asStateFlow()

    private val _torchEnabled = MutableStateFlow(false)
    val torchEnabled: StateFlow<Boolean> = _torchEnabled.asStateFlow()

    private val _hasPermission = MutableStateFlow(false)
    val hasPermission: StateFlow<Boolean> = _hasPermission.asStateFlow()

    private var camera: androidx.camera.core.Camera? = null

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

            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA

            cameraProvider.unbindAll()
            camera = cameraProvider.bindToLifecycle(
                ProcessLifecycleOwner.get(),
                cameraSelector,
                preview
            )
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
}
