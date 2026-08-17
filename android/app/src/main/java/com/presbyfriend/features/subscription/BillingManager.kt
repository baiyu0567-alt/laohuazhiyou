package com.presbyfriend.features.subscription

import android.app.Activity
import android.app.Application
import com.android.billingclient.api.*
import com.presbyfriend.PresbyFriendApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class BillingManager(application: Application) {

    private val store = (application as PresbyFriendApp).settingsStore
    private val scope = CoroutineScope(Dispatchers.IO)
    private val billingClient = BillingClient.newBuilder(application)
        .setListener(::onPurchasesUpdated)
        .enablePendingPurchases(
            PendingPurchasesParams.newBuilder()
                .enableOneTimeProducts()
                .enablePrepaidPlans()
                .build()
        )
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
        val productList = productIds.map { id ->
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(id)
                .setProductType(BillingClient.ProductType.SUBS)
                .build()
        }

        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(productList)
            .build()

        billingClient.queryProductDetailsAsync(params) { _, result ->
            _products.value = result.productDetailsList
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
        ) { _, purchases ->
            val isPro = purchases.any { productIds.contains(it.products.firstOrNull()) }
            if (isPro) {
                scope.launch { store.setIsPro(true) }
            }
            onResult(isPro)
        }
    }

    private fun onPurchasesUpdated(result: BillingResult, purchases: List<Purchase>?) {
        if (result.responseCode == BillingClient.BillingResponseCode.OK && purchases != null) {
            for (purchase in purchases) {
                if (productIds.contains(purchase.products.firstOrNull())) {
                    scope.launch { store.setIsPro(true) }
                    if (purchase.purchaseState == Purchase.PurchaseState.PURCHASED) {
                        val ackParams = AcknowledgePurchaseParams.newBuilder()
                            .setPurchaseToken(purchase.purchaseToken)
                            .build()
                        billingClient.acknowledgePurchase(ackParams) { _ -> }
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
