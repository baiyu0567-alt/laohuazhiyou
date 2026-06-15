package com.presbyfriend

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
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
import kotlinx.coroutines.launch
import java.net.URLDecoder

class MainActivity : ComponentActivity() {

    private var pendingSharedText: String? = null
    private var pendingSharedUrl: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        handleIntent(intent)

        setContent {
            PresbyFriendTheme {
                val navController = rememberNavController()
                val scope = rememberCoroutineScope()

                val startDestination = if (intent?.getBooleanExtra("launch_magnifier", false) == true) {
                    "magnifier"
                } else {
                    "home"
                }

                NavHost(navController = navController, startDestination = startDestination) {
                    composable("home") {
                        HomeScreen(
                            onNavigateToMagnifier = { navController.navigate("magnifier") },
                            onNavigateToSettings = { navController.navigate("settings") }
                        )
                    }

                    composable("magnifier") {
                        MagnifierScreen(
                            onTextDetected = { text ->
                                navController.navigate("reader/${java.net.URLEncoder.encode(text, "UTF-8")}")
                            },
                            onNavigateBack = { navController.popBackStack() }
                        )
                    }

                    composable(
                        route = "reader/{text}",
                        arguments = listOf(navArgument("text") { type = NavType.StringType })
                    ) { backStackEntry ->
                        val text = backStackEntry.arguments?.getString("text")?.let {
                            java.net.URLDecoder.decode(it, "UTF-8")
                        } ?: ""
                        ReaderScreen(
                            initialText = text,
                            onNavigateBack = { navController.popBackStack() }
                        )
                    }

                    composable("settings") {
                        SettingsScreen(
                            onNavigateToPaywall = { navController.navigate("paywall") }
                        )
                    }

                    composable("paywall") {
                        PaywallScreen(
                            onNavigateBack = { navController.popBackStack() }
                        )
                    }
                }

                // Process shared content
                LaunchedEffect(Unit) {
                    pendingSharedText?.let { text ->
                        navController.navigate("reader/${java.net.URLEncoder.encode(text, "UTF-8")}")
                        pendingSharedText = null
                    }
                    pendingSharedUrl?.let { url ->
                        scope.launch {
                            val result = UrlExtractor.extract(url)
                            result.onSuccess { text ->
                                navController.navigate("reader/${java.net.URLEncoder.encode(text, "UTF-8")}")
                            }
                            pendingSharedUrl = null
                        }
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
        when (intent.action) {
            Intent.ACTION_SEND -> {
                val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT) ?: ""
                if (sharedText.startsWith("http://") || sharedText.startsWith("https://")) {
                    pendingSharedUrl = sharedText
                } else {
                    pendingSharedText = sharedText
                }
            }
            Intent.ACTION_PROCESS_TEXT -> {
                intent.getStringExtra(Intent.EXTRA_PROCESS_TEXT)?.let { text ->
                    pendingSharedText = text
                }
            }
            else -> {
                intent.getStringExtra("text")?.let { text ->
                    pendingSharedText = text
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    onNavigateToMagnifier: () -> Unit,
    onNavigateToSettings: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(L10n.appName)) }
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
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(modifier = Modifier.height(32.dp))

            Button(
                onClick = onNavigateToMagnifier,
                modifier = Modifier.fillMaxWidth().height(64.dp)
            ) {
                Text(stringResource(L10n.magnifierTab))
            }

            Spacer(modifier = Modifier.height(12.dp))

            OutlinedButton(
                onClick = onNavigateToSettings,
                modifier = Modifier.fillMaxWidth().height(48.dp)
            ) {
                Text(stringResource(L10n.settingsTab))
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
