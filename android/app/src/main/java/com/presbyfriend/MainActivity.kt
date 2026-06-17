package com.presbyfriend

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.presbyfriend.core.i18n.L10n
import com.presbyfriend.features.magnifier.MagnifierScreen
import com.presbyfriend.features.reader.ReaderScreen
import com.presbyfriend.features.settings.SettingsScreen
import com.presbyfriend.features.subscription.PaywallScreen
import com.presbyfriend.core.url.UrlExtractor
import com.presbyfriend.core.theme.ReadingTheme
import kotlinx.coroutines.flow.MutableStateFlow
import android.util.Base64
import org.json.JSONArray

class MainActivity : ComponentActivity() {

    private val _sharedText = MutableStateFlow<String?>(null)
    private val _sharedUrl = MutableStateFlow<String?>(null)
    private val _launchMagnifier = MutableStateFlow(false)
    private val _showPaywall = MutableStateFlow(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        val paywallFlag = intent?.getBooleanExtra("show_paywall", false) == true

        // Extract text before setContent to skip home-screen flash on cold start
        val initialText = extractInitialText(intent)
        val launchMagnifierFlag = intent?.getBooleanExtra("launch_magnifier", false) == true
        // Service sent us with empty EXTRA_TEXT → need to read clipboard from foreground
        val needsClipboard = !launchMagnifierFlag && initialText == null &&
            intent?.action == Intent.ACTION_SEND
        val activity = this

        setContent {
            PresbyFriendTheme {
                val navController = rememberNavController()
                val startDestination = when {
                    paywallFlag -> "paywall"
                    launchMagnifierFlag -> "magnifier"
                    initialText != null -> "reader_content/${Base64.encodeToString(initialText.toByteArray(), Base64.URL_SAFE or Base64.NO_WRAP)}"
                    needsClipboard -> "reader_content/__clipboard__"
                    else -> "home"
                }


                // Watch for shared text — triggers on warm start (onNewIntent)
                val sharedText by _sharedText.collectAsState()
                LaunchedEffect(sharedText) {
                    sharedText?.let { raw ->
                        if (raw.isNotBlank()) {
                            navController.navigate("reader_content/${Base64.encodeToString(raw.toByteArray(), Base64.URL_SAFE or Base64.NO_WRAP)}") {
                                popUpTo("home")
                            }
                        }
                        _sharedText.value = null
                    }
                }

                // Watch for magnifier launch from accessibility service
                val launchMagnifier by _launchMagnifier.collectAsState()
                LaunchedEffect(launchMagnifier) {
                    if (launchMagnifier) {
                        navController.navigate("magnifier") {
                            popUpTo("home")
                        }
                        _launchMagnifier.value = false
                    }
                }

                // Watch for paywall trigger
                val showPaywall by _showPaywall.collectAsState()
                LaunchedEffect(showPaywall) {
                    if (showPaywall) {
                        navController.navigate("paywall") {
                            popUpTo("home")
                        }
                        _showPaywall.value = false
                    }
                }

                // Watch for shared URLs
                val sharedUrl by _sharedUrl.collectAsState()
                LaunchedEffect(sharedUrl) {
                    sharedUrl?.let { raw ->
                        val result = UrlExtractor.extract(raw)
                        result.onSuccess { text ->
                            navController.navigate("reader_content/${Base64.encodeToString(text.toByteArray(), Base64.URL_SAFE or Base64.NO_WRAP)}") {
                                popUpTo("home")
                            }
                        }
                        _sharedUrl.value = null
                    }
                }

                NavHost(navController = navController, startDestination = startDestination) {
                    composable("home") {
                        HomeScreen(
                            onNavigateToMagnifier = { navController.navigate("magnifier") },
                            onNavigateToSettings = { navController.navigate("settings") },
                            onNavigateToAccessibility = {
                                val intent = android.content.Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
                                startActivity(intent)
                            }
                        )
                    }

                    composable("magnifier") {
                        MagnifierScreen(
                            onTextDetected = { text ->
                                navController.navigate("reader_content/${Base64.encodeToString(text.toByteArray(), Base64.URL_SAFE or Base64.NO_WRAP)}")
                            },
                            onNavigateBack = {
                                navController.navigate("home") {
                                    popUpTo("magnifier") { inclusive = true }
                                }
                            }
                        )
                    }

                    composable(
                        route = "reader_content/{text}",
                        arguments = listOf(navArgument("text") { type = NavType.StringType })
                    ) { backStackEntry ->
                        val rawText = backStackEntry.arguments?.getString("text")?.let {
                            try {
                                String(Base64.decode(it, Base64.URL_SAFE))
                            } catch (_: Exception) {
                                it  // plain text (e.g., "__clipboard__")
                            }
                        } ?: ""
                        val context = LocalContext.current

                        val paragraphs: List<String>? = remember(rawText) {
                            if (rawText == "__clipboard__") {
                                null // handled below
                            } else try {
                                val arr = JSONArray(rawText)
                                (0 until arr.length()).map { arr.getString(it) }
                            } catch (_: Exception) {
                                null // plain text, not JSON
                            }
                        }

                        var displayText by remember { mutableStateOf(if (rawText == "__clipboard__") "" else rawText) }

                        if (rawText == "__clipboard__") {
                            LaunchedEffect(Unit) {
                                val clipboard = context.getSystemService(android.content.Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                                val clip = clipboard.primaryClip
                                val text = if (clip != null && clip.itemCount > 0) {
                                    clip.getItemAt(0)?.text?.toString() ?: ""
                                } else ""
                                displayText = text.ifBlank { getString(R.string.accessibility_hint_body) }
                            }
                        }

                        ReaderScreen(
                            initialText = displayText,
                            paragraphs = paragraphs,
                            onNavigateBack = {
                                if (!navController.popBackStack("home", inclusive = false)) {
                                    activity.finish()
                                }
                            }
                        )
                    }

                    composable("settings") {
                        SettingsScreen(
                            onNavigateToPaywall = { navController.navigate("paywall") }
                        )
                    }

                    composable("paywall") {
                        PaywallScreen(
                            onNavigateBack = {
                                if (!navController.popBackStack()) {
                                    activity.finish()
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        intent?.let { handleIntent(it) }
    }

    private fun handleIntent(intent: Intent) {
        if (intent.getBooleanExtra("show_paywall", false)) {
            _showPaywall.value = true
            return
        }
        intent.getStringExtra("extracted_text")?.let { text ->
            if (text.isNotBlank()) {
                _sharedText.value = text
                return
            }
        }
        if (intent.getBooleanExtra("launch_magnifier", false)) {
            _launchMagnifier.value = true
            return
        }
        when (intent.action) {
            Intent.ACTION_SEND -> {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: ""
                when {
                    text.startsWith("http://") || text.startsWith("https://") ->
                        _sharedUrl.value = text
                    text.isNotBlank() ->
                        _sharedText.value = text
                    // empty text: do nothing (don't fallback to stale clipboard)
                }
            }
            Intent.ACTION_PROCESS_TEXT -> {
                intent.getStringExtra(Intent.EXTRA_PROCESS_TEXT)?.let { text ->
                    _sharedText.value = text
                }
            }
        }
    }

    // Extract text from intent for cold-start startDestination computation.
    // Does NOT read clipboard — that's done later when the reader composable is active.
    private fun extractInitialText(intent: Intent?): String? {
        intent ?: return null
        val action = intent.action ?: return null
        val text = when (action) {
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT) ?: ""
            Intent.ACTION_PROCESS_TEXT -> intent.getStringExtra(Intent.EXTRA_PROCESS_TEXT) ?: ""
            else -> return null
        }
        if (text.isBlank()) {
            return null
        }
        if (text.startsWith("http://") || text.startsWith("https://")) {
            _sharedUrl.value = text
            return null
        }
        return text
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    onNavigateToMagnifier: () -> Unit,
    onNavigateToSettings: () -> Unit,
    onNavigateToAccessibility: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        stringResource(L10n.appName),
                        style = MaterialTheme.typography.headlineLarge
                    )
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(32.dp),
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = stringResource(id = L10n.appSubtitle),
                style = MaterialTheme.typography.headlineMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(modifier = Modifier.height(40.dp))

            Button(
                onClick = onNavigateToMagnifier,
                modifier = Modifier.fillMaxWidth().height(80.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = ReadingTheme.SEPIA.backgroundColor,
                    contentColor = ReadingTheme.SEPIA.textColor
                )
            ) {
                Text(
                    stringResource(L10n.magnifierTab),
                    style = MaterialTheme.typography.titleMedium
                )
            }

            Spacer(modifier = Modifier.height(16.dp))

            OutlinedButton(
                onClick = onNavigateToAccessibility,
                modifier = Modifier.fillMaxWidth().height(80.dp)
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        stringResource(L10n.enableAccessibility),
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        stringResource(L10n.accessibilityHint),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            OutlinedButton(
                onClick = onNavigateToSettings,
                modifier = Modifier.fillMaxWidth().height(80.dp)
            ) {
                Text(
                    stringResource(L10n.settingsTab),
                    style = MaterialTheme.typography.titleMedium
                )
            }

        }
    }
}

@Composable
fun PresbyFriendTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(),
        content = content
    )
}
