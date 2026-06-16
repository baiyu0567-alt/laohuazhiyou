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
import kotlinx.coroutines.flow.MutableStateFlow
import java.net.URLEncoder
import java.net.URLDecoder

class MainActivity : ComponentActivity() {

    private val _sharedText = MutableStateFlow<String?>(null)
    private val _sharedUrl = MutableStateFlow<String?>(null)

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

                // Watch for shared text — triggers on initial launch AND onNewIntent
                val sharedText by _sharedText.collectAsState()
                LaunchedEffect(sharedText) {
                    sharedText?.let { raw ->
                        if (raw.isNotBlank()) {
                            navController.navigate("reader_content/${URLEncoder.encode(raw, "UTF-8")}") {
                                popUpTo("home")
                            }
                        }
                        _sharedText.value = null
                    }
                }

                // Watch for shared URLs
                val sharedUrl by _sharedUrl.collectAsState()
                LaunchedEffect(sharedUrl) {
                    sharedUrl?.let { raw ->
                        val result = UrlExtractor.extract(raw)
                        result.onSuccess { text ->
                            navController.navigate("reader_content/${URLEncoder.encode(text, "UTF-8")}") {
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
                            onNavigateToSettings = { navController.navigate("settings") }
                        )
                    }

                    composable("magnifier") {
                        MagnifierScreen(
                            onTextDetected = { text ->
                                navController.navigate("reader_content/${URLEncoder.encode(text, "UTF-8")}")
                            },
                            onNavigateBack = { navController.popBackStack() }
                        )
                    }

                    composable(
                        route = "reader_content/{text}",
                        arguments = listOf(navArgument("text") { type = NavType.StringType })
                    ) { backStackEntry ->
                        val text = backStackEntry.arguments?.getString("text")?.let {
                            URLDecoder.decode(it, "UTF-8")
                        } ?: ""
                        ReaderScreen(
                            initialText = text,
                            onNavigateBack = {
                                navController.popBackStack("home", inclusive = false)
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
                            onNavigateBack = { navController.popBackStack() }
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
        when (intent.action) {
            Intent.ACTION_SEND -> {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: ""
                if (text.startsWith("http://") || text.startsWith("https://")) {
                    _sharedUrl.value = text
                } else {
                    _sharedText.value = text
                }
            }
            Intent.ACTION_PROCESS_TEXT -> {
                intent.getStringExtra(Intent.EXTRA_PROCESS_TEXT)?.let { text ->
                    _sharedText.value = text
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
