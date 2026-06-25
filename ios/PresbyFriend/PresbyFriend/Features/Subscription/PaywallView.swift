import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = SubscriptionManager()
    @State private var purchasing = false
    @State private var snackbarMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.orange)

                Text(L10n.upgradePro)
                    .font(.largeTitle.bold())

                Text(L10n.freeLimitReached)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                if manager.products.isEmpty {
                    // Fallback pricing — products not yet configured in App Store Connect
                    fallbackPlanCard(
                        name: L10n.proMonthly,
                        desc: L10n.proMonthlyDesc,
                        price: L10n.proMonthlyPrice
                    )
                    fallbackPlanCard(
                        name: L10n.proYearly,
                        desc: L10n.proYearlyDesc,
                        price: L10n.proYearlyPrice
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(manager.products) { product in
                            Button {
                                purchasing = true
                                Task {
                                    if await manager.purchase(product) {
                                        dismiss()
                                    }
                                    purchasing = false
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(product.displayName).font(.headline)
                                        Text(product.description).font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(product.displayPrice)
                                        .font(.title3.bold())
                                }
                                .padding()
                                .background(.ultraThinMaterial)
                                .cornerRadius(12)
                            }
                            .disabled(purchasing)
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

                Button {
                    Task {
                        if await manager.restorePurchases() {
                            snackbarMessage = L10n.restoreSuccess
                            dismiss()
                        } else {
                            snackbarMessage = L10n.restoreNoPurchases
                        }
                    }
                } label: {
                    Text(L10n.restorePurchases)
                        .font(.body)
                }

                if let msg = snackbarMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .transition(.opacity)
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.close) { dismiss() }
                }
            }
        }
        .task { await manager.loadProducts() }
    }

    @ViewBuilder
    private func fallbackPlanCard(name: String, desc: String, price: String) -> some View {
        Button {
            snackbarMessage = L10n.playStoreComing
            // Auto-dismiss after 2s
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                snackbarMessage = nil
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.headline).foregroundColor(.primary)
                    Text(desc).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text(price).font(.title3.bold()).foregroundColor(.orange)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}
