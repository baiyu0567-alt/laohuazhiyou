import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    /// **App 级的那个唯一实例**，不在这里新建。
    ///
    /// 原先这里是 `@StateObject private var manager = SubscriptionManager()`——sheet
    /// 每弹一次就造一个新对象，于是「买了之后关掉付费墙，Pro 状态就没了」，而 App
    /// 其他地方更是完全读不到用户是不是 Pro。见 `SubscriptionManager` 的文档。
    @EnvironmentObject private var subscription: SubscriptionManager
    @State private var purchasing = false
    /// 正在向 Apple 对账。期间禁用按钮——连点会叠起多次 `AppStore.sync()`。
    @State private var restoring = false
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

                if subscription.products.isEmpty {
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
                        ForEach(subscription.products) { product in
                            Button {
                                purchasing = true
                                Task {
                                    if await subscription.purchase(product) {
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
                    restoring = true
                    Task {
                        if await subscription.restorePurchases() {
                            // ⚠️ **成功后不能立刻 `dismiss()`**：sheet 一关，这句
                            // 「已恢复」就永远不会被渲染——用户做了正确的动作，
                            // 却什么反馈都没看到。原先就是「先赋值再关」，等于没写。
                            // 停一下让他读到，再关。
                            snackbarMessage = L10n.restoreSuccess
                            try? await Task.sleep(nanoseconds: 1_800_000_000)
                            dismiss()
                        } else {
                            // 「没有购买」和「查询本身失败了」是两件事，不能都报
                            // 「没找到购买记录」。失败时 `storeMessage` 里已经有原因，
                            // 那一句由下面的提示条显示，这里就不覆盖它。
                            snackbarMessage = subscription.storeMessage == nil
                                ? L10n.restoreNoPurchases : nil
                        }
                        restoring = false
                    }
                } label: {
                    Text(L10n.restorePurchases)
                        .font(.body)
                }
                .disabled(restoring)

                // 购买/恢复失败不再静默：`SubscriptionManager` 会把**已本地化**的一句话
                // 放进 `storeMessage`，这里兜底显示。原先 `catch {}` 吞掉一切，用户点了
                // 按钮什么都没发生，看上去就是「App 坏了」。
                if let msg = snackbarMessage ?? subscription.storeMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
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
        .task { await subscription.loadProducts() }
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
