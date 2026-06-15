package com.presbyfriend.features.magnifier

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.presbyfriend.core.i18n.L10n

@Composable
fun ZoomSlider(
    zoomLevel: Float,
    onZoomChange: (Float) -> Unit,
    modifier: Modifier = Modifier
) {
    val minZoom = 1.0f
    val maxZoom = 8.0f

    Column(modifier = modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = "${stringResource(L10n.zoomLabel)} ${zoomLevel.toInt()}×",
            color = MaterialTheme.colorScheme.onSurface
        )

        Spacer(modifier = Modifier.height(8.dp))

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
                .clip(RoundedCornerShape(24.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f))
                .pointerInput(Unit) {
                    detectHorizontalDragGestures { change, _ ->
                        val fraction = change.position.x / size.width
                        val newZoom = (minZoom + (maxZoom - minZoom) * fraction)
                            .coerceIn(minZoom, maxZoom)
                        onZoomChange(newZoom)
                        change.consume()
                    }
                },
            contentAlignment = Alignment.CenterStart
        ) {
            // Filled portion
            val fraction = (zoomLevel - minZoom) / (maxZoom - minZoom)
            Box(
                modifier = Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(fraction)
                    .clip(RoundedCornerShape(24.dp))
                    .background(MaterialTheme.colorScheme.primary)
            )

            // Thumb
            Box(
                modifier = Modifier
                    .padding(start = (fraction * 300).dp.coerceAtMost(300.dp)) // approximate
                    .size(32.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primary)
            )
        }
    }
}
