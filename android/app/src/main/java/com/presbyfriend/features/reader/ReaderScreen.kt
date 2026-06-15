package com.presbyfriend.features.reader

import android.app.Application
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.presbyfriend.core.i18n.L10n
import com.presbyfriend.core.theme.ReadingTheme

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReaderScreen(
    initialText: String = "",
    onNavigateBack: () -> Unit
) {
    val context = LocalContext.current
    val application = context.applicationContext as Application
    val viewModel = remember { ReaderViewModel(application) }

    LaunchedEffect(initialText) {
        if (initialText.isNotBlank()) {
            viewModel.setText(initialText)
        }
    }

    val text by viewModel.text.collectAsState()
    val fontSize by viewModel.fontSize.collectAsState()
    val theme by viewModel.theme.collectAsState()
    val lineHeight by viewModel.lineHeight.collectAsState()
    val letterSpacing by viewModel.letterSpacing.collectAsState()
    val rulerEnabled by viewModel.rulerEnabled.collectAsState()
    val isSpeaking by viewModel.isSpeaking.collectAsState()
    val showControls by viewModel.showControls.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(L10n.readingMode)) },
                navigationIcon = {
                    TextButton(onClick = onNavigateBack) {
                        Text(stringResource(L10n.close))
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.toggleSpeaking(application) }) {
                        Text(
                            if (isSpeaking) stringResource(L10n.stopReading)
                            else stringResource(L10n.readAloud)
                        )
                    }
                    IconButton(onClick = { viewModel.toggleControls() }) {
                        Text(stringResource(L10n.showControls))
                    }
                }
            )
        },
        containerColor = theme.backgroundColor
    ) { padding ->
        Box(modifier = Modifier.padding(padding)) {
            // Text content
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 24.dp, vertical = 16.dp)
            ) {
                Text(
                    text = text.ifBlank { stringResource(L10n.tapTextToRead) },
                    style = TextStyle(
                        fontSize = fontSize.sp,
                        lineHeight = (fontSize * lineHeight).sp,
                        letterSpacing = letterSpacing.sp,
                        color = theme.textColor,
                        fontFamily = FontFamily.Serif
                    )
                )
            }

            // Reading ruler overlay
            if (rulerEnabled) {
                ReadingRulerOverlay(
                    lineHeight = fontSize * lineHeight,
                    accentColor = theme.accentColor
                )
            }

            // Controls panel
            if (showControls) {
                ControlsPanel(
                    fontSize = fontSize,
                    theme = theme,
                    lineHeight = lineHeight,
                    letterSpacing = letterSpacing,
                    rulerEnabled = rulerEnabled,
                    onFontSizeChange = { viewModel.adjustFontSize(it) },
                    onThemeChange = { viewModel.setTheme(it) },
                    onLineHeightChange = { viewModel.adjustLineHeight(it) },
                    onLetterSpacingChange = { viewModel.adjustLetterSpacing(it) },
                    onRulerToggle = { viewModel.toggleRuler() },
                    modifier = Modifier.align(Alignment.BottomCenter)
                )
            }
        }
    }
}

@Composable
private fun ControlsPanel(
    fontSize: Float,
    theme: ReadingTheme,
    lineHeight: Float,
    letterSpacing: Float,
    rulerEnabled: Boolean,
    onFontSizeChange: (Float) -> Unit,
    onThemeChange: (ReadingTheme) -> Unit,
    onLineHeightChange: (Float) -> Unit,
    onLetterSpacingChange: (Float) -> Unit,
    onRulerToggle: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 8.dp,
        shadowElevation = 8.dp
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            // Font size
            Text(stringResource(L10n.fontSize) + ": ${fontSize.toInt()}sp")
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { onFontSizeChange(-4f) }) { Text("-") }
                Slider(
                    value = fontSize,
                    onValueChange = { onFontSizeChange(it - fontSize) },
                    valueRange = 24f..72f,
                    steps = 11,
                    modifier = Modifier.weight(1f)
                )
                TextButton(onClick = { onFontSizeChange(4f) }) { Text("+") }
            }

            // Theme
            Text(stringResource(L10n.themeLabel))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ReadingTheme.entries.forEach { t ->
                    Surface(
                        onClick = { onThemeChange(t) },
                        modifier = Modifier.size(48.dp),
                        shape = MaterialTheme.shapes.small,
                        color = t.backgroundColor,
                        border = if (theme == t)
                            androidx.compose.foundation.BorderStroke(2.dp, t.accentColor)
                        else null
                    ) {}
                }
            }

            // Line height
            Text(stringResource(L10n.lineHeight) + ": ${"%.1f".format(lineHeight)}")
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { onLineHeightChange(-0.2f) }) { Text("-") }
                Slider(
                    value = lineHeight,
                    onValueChange = { onLineHeightChange(it - lineHeight) },
                    valueRange = 1.0f..3.0f,
                    modifier = Modifier.weight(1f)
                )
                TextButton(onClick = { onLineHeightChange(0.2f) }) { Text("+") }
            }

            // Letter spacing
            Text(stringResource(L10n.letterSpacing) + ": ${"%.1f".format(letterSpacing)}sp")
            Row(verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { onLetterSpacingChange(-0.5f) }) { Text("-") }
                Slider(
                    value = letterSpacing,
                    onValueChange = { onLetterSpacingChange(it - letterSpacing) },
                    valueRange = 0f..5f,
                    modifier = Modifier.weight(1f)
                )
                TextButton(onClick = { onLetterSpacingChange(0.5f) }) { Text("+") }
            }

            // Reading ruler
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(L10n.readingRuler))
                Spacer(Modifier.weight(1f))
                Switch(checked = rulerEnabled, onCheckedChange = { onRulerToggle() })
            }
        }
    }
}
