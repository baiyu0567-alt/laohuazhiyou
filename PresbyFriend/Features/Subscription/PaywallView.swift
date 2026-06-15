import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = SubscriptionManager()
    @State private var purchasing = false

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

                Button("Restore Purchases") {
                    Task { await manager.restorePurchases() }
                }
                .font(.caption)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await manager.loadProducts() }
    }
}
