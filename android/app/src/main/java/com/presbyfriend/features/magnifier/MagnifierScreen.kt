package com.presbyfriend.features.magnifier

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.presbyfriend.core.i18n.L10n

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MagnifierScreen(
    onTextDetected: (String) -> Unit,
    onNavigateBack: () -> Unit
) {
    val context = LocalContext.current
    val viewModel = remember { MagnifierViewModel(context.applicationContext as android.app.Application) }

    val zoomLevel by viewModel.zoomLevel.collectAsState()
    val torchEnabled by viewModel.torchEnabled.collectAsState()
    val hasPermission by viewModel.hasPermission.collectAsState()
    val detectedTexts by viewModel.detectedTexts.collectAsState()

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        viewModel.checkPermission()
    }

    LaunchedEffect(Unit) {
        if (!viewModel.hasPermission.value) {
            permissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(L10n.magnifierTab)) },
                navigationIcon = {
                    TextButton(onClick = onNavigateBack) {
                        Text(stringResource(L10n.close))
                    }
                }
            )
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            if (!hasPermission) {
                Text(
                    text = stringResource(L10n.cameraPermissionRequired),
                    modifier = Modifier.align(Alignment.Center),
                    textAlign = TextAlign.Center
                )
            } else {
                // Camera preview
                AndroidView(
                    factory = { ctx ->
                        PreviewView(ctx).also { previewView ->
                            viewModel.startCamera(previewView)
                        }
                    },
                    modifier = Modifier.fillMaxSize()
                )

                // Detected text overlay
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .align(Alignment.TopCenter)
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    detectedTexts.take(5).forEach { text ->
                        Surface(
                            onClick = { onTextDetected(text) },
                            shape = MaterialTheme.shapes.small,
                            color = MaterialTheme.colorScheme.surface.copy(alpha = 0.8f)
                        ) {
                            Text(
                                text = text,
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                                style = MaterialTheme.typography.bodyMedium
                            )
                        }
                    }
                }

                // Controls at bottom
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .align(Alignment.BottomCenter)
                        .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    // Zoom slider
                    ZoomSlider(
                        zoomLevel = zoomLevel,
                        onZoomChange = { viewModel.setZoom(it) }
                    )

                    // Torch button
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.Center
                    ) {
                        FilledTonalButton(onClick = { viewModel.toggleTorch() }) {
                            Text(stringResource(L10n.flashlight) +
                                if (torchEnabled) " ON" else " OFF")
                        }
                    }
                }
            }
        }
    }
}
