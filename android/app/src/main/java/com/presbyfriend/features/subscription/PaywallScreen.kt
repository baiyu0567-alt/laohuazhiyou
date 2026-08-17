package com.presbyfriend.features.subscription

import android.app.Activity
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
import com.presbyfriend.R
import com.presbyfriend.core.i18n.L10n
import com.presbyfriend.core.theme.ReadingTheme
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PaywallScreen(
    onNavigateBack: () -> Unit
) {
    val context = LocalContext.current
    val activity = context as? Activity
    val billingManager = remember { BillingManager(context.applicationContext as Application) }
    val products by billingManager.products.collectAsState()
    val isReady by billingManager.isReady.collectAsState()
    var purchasing by remember { mutableStateOf(false) }
    var restoring by remember { mutableStateOf(false) }
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

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
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
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

            if (isReady && products.isNotEmpty()) {
                products.forEach { product ->
                    Card(
                        onClick = {
                            if (!purchasing) {
                                purchasing = true
                                activity?.let { act ->
                                    billingManager.purchase(
                                        activity = act,
                                        product = product
                                    ) { success ->
                                        purchasing = false
                                        if (success) onNavigateBack()
                                    }
                                }
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                        enabled = !purchasing,
                        colors = CardDefaults.cardColors(
                            containerColor = ReadingTheme.SEPIA.backgroundColor
                        )
                    ) {
                        Row(
                            modifier = Modifier.padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = product.name,
                                    style = MaterialTheme.typography.titleMedium,
                                    color = ReadingTheme.SEPIA.textColor
                                )
                                Text(
                                    text = product.description,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = ReadingTheme.SEPIA.textColor.copy(alpha = 0.7f)
                                )
                            }
                            Text(
                                text = product.subscriptionOfferDetails
                                    ?.firstOrNull()
                                    ?.pricingPhases
                                    ?.pricingPhaseList
                                    ?.firstOrNull()
                                    ?.formattedPrice ?: "",
                                style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                                color = ReadingTheme.SEPIA.accentColor
                            )
                        }
                    }
                }
            } else if (isReady) {
                // Billing connected but no products in Play Console yet — show hardcoded info
                val fallbackPlans = listOf(
                    Triple(stringResource(R.string.pro_monthly), stringResource(R.string.pro_monthly_desc), stringResource(R.string.pro_monthly_price)),
                    Triple(stringResource(R.string.pro_yearly), stringResource(R.string.pro_yearly_desc), stringResource(R.string.pro_yearly_price))
                )
                fallbackPlans.forEach { (name, desc, price) ->
                    Card(
                        onClick = {
                            billingManager.refresh()
                            scope.launch { snackbarHostState.showSnackbar(context.getString(R.string.play_store_coming)) }
                        },
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(12.dp),
                        colors = CardDefaults.cardColors(
                            containerColor = ReadingTheme.SEPIA.backgroundColor
                        )
                    ) {
                        Row(
                            modifier = Modifier.padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = name,
                                    style = MaterialTheme.typography.titleMedium,
                                    color = ReadingTheme.SEPIA.textColor
                                )
                                Text(
                                    text = desc,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = ReadingTheme.SEPIA.textColor.copy(alpha = 0.7f)
                                )
                            }
                            Text(
                                text = price,
                                style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                                color = ReadingTheme.SEPIA.accentColor
                            )
                        }
                    }
                }
            } else {
                CircularProgressIndicator()
            }

            OutlinedButton(
                onClick = {
                    if (!restoring) {
                        restoring = true
                        billingManager.restorePurchases { success ->
                            restoring = false
                            val msg = if (success) {
                                context.getString(R.string.restore_success)
                            } else {
                                context.getString(R.string.restore_no_purchases)
                            }
                            scope.launch { snackbarHostState.showSnackbar(msg) }
                            if (success) onNavigateBack()
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth().height(56.dp),
                enabled = !restoring
            ) {
                if (restoring) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                } else {
                    Text(stringResource(L10n.restorePurchases))
                }
            }
        }
    }
}
