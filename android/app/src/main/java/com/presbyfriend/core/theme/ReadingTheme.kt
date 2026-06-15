package com.presbyfriend.core.theme

import androidx.compose.ui.graphics.Color

enum class ReadingTheme(
    val backgroundColor: Color,
    val textColor: Color,
    val accentColor: Color,
    val displayNameRes: Int
) {
    WHITE(
        backgroundColor = Color(0xFFFFFFFF),
        textColor = Color(0xFF1A1A1A),
        accentColor = Color(0xFF007AFF),
        displayNameRes = com.presbyfriend.R.string.theme_white
    ),
    SEPIA(
        backgroundColor = Color(0xFFF5ECD7),
        textColor = Color(0xFF5B4636),
        accentColor = Color(0xFFC17D3B),
        displayNameRes = com.presbyfriend.R.string.theme_sepia
    ),
    DARK(
        backgroundColor = Color(0xFF1A1A1A),
        textColor = Color(0xFFE8E8E8),
        accentColor = Color(0xFFFFD60A),
        displayNameRes = com.presbyfriend.R.string.theme_dark
    ),
    YELLOW(
        backgroundColor = Color(0xFFFFF8E1),
        textColor = Color(0xFF333333),
        accentColor = Color(0xFFFF6F00),
        displayNameRes = com.presbyfriend.R.string.theme_yellow
    );

    companion object {
        fun fromName(name: String, default: ReadingTheme = DARK): ReadingTheme {
            return entries.find { it.name.equals(name, ignoreCase = true) } ?: default
        }
    }
}
