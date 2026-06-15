package com.presbyfriend.features.subscription

import android.app.Activity
import android.app.Application
import com.android.billingclient.api.*
import com.presbyfriend.PresbyFriendApp
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class BillingManager(application: Application) {

    private val store = (application as PresbyFriendApp).settingsStore
    private val billingClient = BillingClient.newBuilder(application)
        .setListener(::onPurchasesUpdated)
        .enablePendingPurchases()
        .build()

    private val _products = MutableStateFlow<List<ProductDetails>>(emptyList())
    val products: StateFlow<List<ProductDetails>> = _products.asStateFlow()

    private val _isReady = MutableStateFlow(false)
    val isReady: StateFlow<Boolean> = _isReady.asStateFlow()

    private val productIds = listOf(
        "com.presbyfriend.pro.monthly",
        "com.presbyfriend.pro.yearly"
    )

    private var pendingCallback: ((Boolean) -> Unit)? = null

    fun startConnection() {
        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingServiceDisconnected() {
                _isReady.value = false
            }

            override fun onBillingSetupFinished(result: BillingResult) {
                _isReady.value = result.responseCode == BillingClient.BillingResponseCode.OK
                if (_isReady.value) loadProducts()
            }
        })
    }

    private fun loadProducts() {
        val params = QueryProductDetailsParams.newBuilder().apply {
            productIds.forEach { id ->
                setProductList(
                    listOf(
                        QueryProductDetailsParams.Product.newBuilder()
                            .setProductId(id)
                            .setProductType(BillingClient.ProductType.SUBS)
                            .build()
                    )
                )
            }
        }.build()

        billingClient.queryProductDetailsAsync(params) { result, details ->
            _products.value = details ?: emptyList()
        }
    }

    fun purchase(activity: Activity, product: ProductDetails, onResult: (Boolean) -> Unit) {
        pendingCallback = onResult
        val offerToken = product.subscriptionOfferDetails?.firstOrNull()?.offerToken ?: ""
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(
                listOf(
                    BillingFlowParams.ProductDetailsParams.newBuilder()
                        .setProductDetails(product)
                        .setOfferToken(offerToken)
                        .build()
                )
            )
            .build()
        billingClient.launchBillingFlow(activity, params)
    }

    fun restorePurchases(onResult: (Boolean) -> Unit) {
        billingClient.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder()
                .setProductType(BillingClient.ProductType.SUBS)
                .build()
        ) { result, purchases ->
            val isPro = purchases.any { productIds.contains(it.products.firstOrNull()) }
            if (isPro) {
                kotlinx.coroutines.runBlocking { store.setIsPro(true) }
            }
            onResult(isPro)
        }
    }

    private fun onPurchasesUpdated(result: BillingResult, purchases: List<Purchase>?) {
        if (result.responseCode == BillingClient.BillingResponseCode.OK && purchases != null) {
            for (purchase in purchases) {
                if (productIds.contains(purchase.products.firstOrNull())) {
                    kotlinx.coroutines.runBlocking { store.setIsPro(true) }
                    if (purchase.purchaseState == Purchase.PurchaseState.PURCHASED) {
                        purchase.acknowledgeAsync {}.let {} // Acknowledge silently
                    }
                    pendingCallback?.invoke(true)
                    pendingCallback = null
                    return
                }
            }
        }
        pendingCallback?.invoke(false)
        pendingCallback = null
    }
}
