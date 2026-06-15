package com.presbyfriend.features.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp

@Composable
fun ReadingRulerOverlay(
    lineHeight: Float,
    accentColor: Color,
    modifier: Modifier = Modifier
) {
    var rulerY by remember { mutableFloatStateOf(0f) }

    Box(
        modifier = modifier
            .fillMaxSize()
            .pointerInput(Unit) {
                detectVerticalDragGestures { _, dragAmount ->
                    rulerY = (rulerY + dragAmount).coerceAtLeast(0f)
                }
            }
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height((lineHeight * 1.2f).dp)
                .offset(y = rulerY.dp)
                .background(accentColor.copy(alpha = 0.12f))
        )
    }
}
