package com.presbyfriend.features.subscription

import android.app.Application
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.presbyfriend.core.i18n.L10n

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaywallScreen(
    onNavigateBack: () -> Unit
) {
    val context = LocalContext.current
    val billingManager = remember { BillingManager(context.applicationContext as Application) }
    val products by billingManager.products.collectAsState()
    val isReady by billingManager.isReady.collectAsState()
    var purchasing by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        billingManager.startConnection()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(L10n.upgradePro)) },
                navigationIcon = {
                    TextButton(onClick = onNavigateBack) {
                        Text(stringResource(L10n.close))
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp)
        ) {
            Text(
                text = "👑",
                fontSize = 64.sp
            )

            Text(
                text = stringResource(L10n.upgradePro),
                style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold)
            )

            Text(
                text = stringResource(L10n.freeLimitReached),
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            if (isReady) {
                products.forEach { product ->
                    Card(
                        onClick = {
                            if (!purchasing) {
                                purchasing = true
                                billingManager.purchase(
                                    activity = context as android.app.Activity,
                                    product = product
                                ) { success ->
                                    purchasing = false
                                    if (success) onNavigateBack()
                                }
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                        enabled = !purchasing
                    ) {
                        Row(
                            modifier = Modifier.padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = product.name,
                                    style = MaterialTheme.typography.titleMedium
                                )
                                Text(
                                    text = product.description,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            Text(
                                text = product.subscriptionOfferDetails
                                    ?.firstOrNull()
                                    ?.pricingPhases
                                    ?.pricingPhaseList
                                    ?.firstOrNull()
                                    ?.formattedPrice ?: "",
                                style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold)
                            )
                        }
                    }
                }
            } else {
                CircularProgressIndicator()
            }

            TextButton(onClick = {
                billingManager.restorePurchases { success ->
                    if (success) onNavigateBack()
                }
            }) {
                Text(stringResource(L10n.restorePurchases))
            }
        }
    }
}
