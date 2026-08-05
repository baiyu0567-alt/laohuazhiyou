package com.presbyfriend.features.settings

import android.app.Activity
import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.presbyfriend.core.i18n.L10n
import com.presbyfriend.core.theme.ReadingTheme

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onNavigateToPaywall: () -> Unit
) {
    val context = LocalContext.current
    val viewModel = remember { SettingsViewModel(context.applicationContext as android.app.Application) }

    val fontSize by viewModel.fontSize.collectAsState()
    val theme by viewModel.theme.collectAsState()
    val lineHeight by viewModel.lineHeight.collectAsState()
    val letterSpacing by viewModel.letterSpacing.collectAsState()
    val rulerEnabled by viewModel.rulerEnabled.collectAsState()
    val language by viewModel.language.collectAsState()

    var showResetDialog by remember { mutableStateOf(false) }
    var showDisclosureDialog by remember { mutableStateOf(false) }
    var languageExpanded by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(title = { Text(stringResource(L10n.settingsTab)) })
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            // Auto-save hint
            Text(
                stringResource(L10n.settingsAutoSave),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.primary,
                modifier = Modifier.fillMaxWidth(),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )

            // Font size
            Text(
                stringResource(L10n.defaultFont),
                style = MaterialTheme.typography.titleSmall
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("${fontSize.toInt()}sp")
                Spacer(Modifier.weight(1f))
                TextButton(onClick = { viewModel.setFontSize(maxOf(24f, fontSize - 4f)) }) {
                    Text("-")
                }
                Slider(
                    value = fontSize,
                    onValueChange = { viewModel.setFontSize(it) },
                    valueRange = 24f..72f,
                    steps = 11,
                    modifier = Modifier.width(150.dp)
                )
                TextButton(onClick = { viewModel.setFontSize(minOf(72f, fontSize + 4f)) }) {
                    Text("+")
                }
            }

            // Theme
            Text(
                stringResource(L10n.defaultTheme),
                style = MaterialTheme.typography.titleSmall
            )
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ReadingTheme.entries.forEach { t ->
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Surface(
                            onClick = { viewModel.setTheme(t) },
                            modifier = Modifier.size(56.dp),
                            shape = RoundedCornerShape(8.dp),
                            color = t.backgroundColor,
                            border = if (theme == t)
                                androidx.compose.foundation.BorderStroke(3.dp, t.accentColor)
                            else null
                        ) {}
                        Text(
                            stringResource(t.displayNameRes),
                            style = MaterialTheme.typography.labelSmall
                        )
                    }
                }
            }

            // Reading ruler
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(stringResource(L10n.readingRuler), style = MaterialTheme.typography.titleSmall)
                    Text(
                        stringResource(L10n.rulerDescription),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Switch(checked = rulerEnabled, onCheckedChange = { viewModel.setRulerEnabled(it) })
            }

            // Language
            Text(
                stringResource(L10n.languageLabel),
                style = MaterialTheme.typography.titleSmall
            )
            ExposedDropdownMenuBox(
                expanded = languageExpanded,
                onExpandedChange = { languageExpanded = it }
            ) {
                OutlinedTextField(
                    value = viewModel.availableLanguages.find { it.first == language }?.second ?: "English",
                    onValueChange = {},
                    readOnly = true,
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = languageExpanded) },
                    modifier = Modifier.menuAnchor().fillMaxWidth()
                )
                ExposedDropdownMenu(
                    expanded = languageExpanded,
                    onDismissRequest = { languageExpanded = false }
                ) {
                    viewModel.availableLanguages.forEach { (code, name) ->
                        DropdownMenuItem(
                            text = { Text(name) },
                            onClick = {
                                viewModel.setLanguage(code)
                                languageExpanded = false
                                L10n.applyLocale(context, code)
                                (context as? Activity)?.recreate()
                            }
                        )
                    }
                }
            }

            // Floating magnifier button (accessibility service)
            HorizontalDivider()
            Column {
                Text(
                    stringResource(L10n.accessibilityDisclosureTitle),
                    style = MaterialTheme.typography.titleSmall
                )
                Text(
                    stringResource(L10n.accessibilityHint),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(8.dp))
                OutlinedButton(
                    onClick = { showDisclosureDialog = true },
                    modifier = Modifier.fillMaxWidth().height(48.dp)
                ) {
                    Text(stringResource(L10n.enableAccessibility))
                }
            }

            // Pro upgrade
            Button(
                onClick = onNavigateToPaywall,
                modifier = Modifier.fillMaxWidth().height(56.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = ReadingTheme.SEPIA.backgroundColor,
                    contentColor = ReadingTheme.SEPIA.textColor
                )
            ) {
                Text(
                    "${stringResource(L10n.upgradePro)}",
                    style = MaterialTheme.typography.titleMedium
                )
            }

            // Reset
            OutlinedButton(
                onClick = { showResetDialog = true },
                modifier = Modifier.fillMaxWidth().height(56.dp),
                colors = ButtonDefaults.outlinedButtonColors(
                    contentColor = MaterialTheme.colorScheme.error
                )
            ) {
                Text(
                    stringResource(L10n.resetSettings),
                    style = MaterialTheme.typography.titleMedium
                )
            }

            // Version
            Text(
                stringResource(L10n.versionFooter),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.fillMaxWidth(),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center
            )
        }
    }

    if (showDisclosureDialog) {
        AlertDialog(
            onDismissRequest = { showDisclosureDialog = false },
            title = { Text(stringResource(L10n.accessibilityDisclosureTitle)) },
            text = {
                Text(stringResource(L10n.accessibilityDisclosureBody) + "\n\n" +
                     stringResource(L10n.accessibilityDisclosureNote))
            },
            confirmButton = {
                TextButton(onClick = {
                    showDisclosureDialog = false
                    context.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                }) {
                    Text(stringResource(L10n.openAccessibilitySettings))
                }
            },
            dismissButton = {
                TextButton(onClick = { showDisclosureDialog = false }) {
                    Text(stringResource(L10n.close))
                }
            }
        )
    }

    if (showResetDialog) {
        AlertDialog(
            onDismissRequest = { showResetDialog = false },
            title = { Text(stringResource(L10n.resetSettings)) },
            text = { Text(stringResource(L10n.resetConfirm)) },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.reset()
                    showResetDialog = false
                }) {
                    Text(stringResource(L10n.resetSettings), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showResetDialog = false }) {
                    Text(stringResource(L10n.close))
                }
            }
        )
    }
}
