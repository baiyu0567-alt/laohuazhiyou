package com.presbyfriend.core.capture

/**
 * A text block with its vertical position ratio (0.0 = top, 1.0 = bottom).
 * Used to filter out bottom-screen noise (keyboards, nav bars, gesture handles).
 */
data class PositionedBlock(
    val text: String,
    val topYRatio: Float
)
