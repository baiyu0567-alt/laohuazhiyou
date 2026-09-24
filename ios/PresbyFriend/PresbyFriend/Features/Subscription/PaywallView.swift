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

    /// 使用条款。**用 Apple 的标准 EULA**：没有自己写一份 EULA 时，条款 3.1.2 允许
    /// 直接链这一份，不必为此新起一个网页。
    private static let termsOfUseURL =
        URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// 隐私政策。**必须与 App Store Connect 里填的那个 URL 一致**——审核员会两边都点。
    private static let privacyPolicyURL =
        URL(string: "https://baiyu0567-alt.github.io/laohuazhiyou/privacy/")!

    var body: some View {
        NavigationStack {
            // 多了披露段和条款链接之后内容会超过一屏，小屏 + 横屏尤其。不滚动的话
            // 底部那段——**正是审核要看的那段**——会被挤出屏幕。
            ScrollView {
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

                    productSection

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

                    // 披露与条款**紧跟在可购买的商品之后**：条款 3.1.2 要的是这一屏自己
                    // 说清楚，不是「在别处能找到」。没有商品可买时不显示——对着一个
                    // 只有报错的界面念扣款规则，是答非所问。
                    if !subscription.products.isEmpty {
                        disclosureSection
                    }
                }
                .padding()
                // `ScrollView` 里 `VStack` 不会自动撑满宽度，不写这句所有内容会挤在中间。
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.close) { dismiss() }
                }
            }
        }
        .task {
            // **上一次弹出的结论不带到这一次。** `storeMessage` 是 App 级的、跨弹出留存
            // （单例），而下面那条提示条是 `snackbarMessage ?? subscription.storeMessage`
            // ——不清的话，用户上一次买失败之后，这一次只是把付费墙打开、什么都没做，
            // 屏幕上就先摆着一句「购买失败，请稍后再试」。那是在对一个什么都没做的人
            // 报错。
            //
            // 清在 `loadProducts()` **之前**：它自己失败时会往里写新的一句，
            // 顺序反过来就把新的那句一起清掉了。
            subscription.storeMessage = nil
            await subscription.loadProducts()
        }
    }

    // MARK: - 商品

    @ViewBuilder
    private var productSection: some View {
        if !subscription.isProductsLoaded {
            // 「还在查」不能和「查过了，一条商品都没有」共用一张脸。首帧渲染
            // 发生在 `.task` 之前，所以这里不加这一支的话，每一次打开付费墙
            // 都会先亮出两张写死的兜底价签再被真商品换掉——最坏的情况是把
            // 假价格当成真的给用户看了一瞬。
            ProgressView()
                .controlSize(.large)
                .padding(.vertical, 40)
        } else if subscription.products.isEmpty {
            // **这里原先摆的是两张写死价签（$2.99/mo、$19.99/yr），点了只说
            // 「即将上线」。已删。** 那是一个**买不了的价格**：商品没配好（或查询失败）
            // 时，用户看到的是具体数字却不是真实价格，而点下去没有任何购买可能。
            // 审核那边也是同一个问题——App 里出现一个卖不了的价格，属于误导。
            // 商品没到位就如实说查询失败，并给一个重试。
            VStack(spacing: 12) {
                Text(L10n.storeError)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                Button(L10n.retry) {
                    Task { await subscription.loadProducts() }
                }
            }
            .padding(.horizontal)
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
                            VStack(alignment: .leading, spacing: 2) {
                                // 名称与说明都来自 App Store Connect，不写死在代码里——
                                // 条款 3.1.2 要求披露的是**这个商品**的名称与价格。
                                Text(product.displayName).font(.headline)
                                if let period = Self.periodText(for: product) {
                                    Text(period)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Text(product.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
    }

    /// 订阅周期，从**商品自己**的 `Product.subscription` 读。
    ///
    /// 不写死「月/年」两个字：周期是商品在 App Store Connect 上的属性，将来改了周期
    /// 而这里还印着旧的那句话，就是一条**虚假披露**——比不写更糟。
    /// 出现本函数没备文案的周期时返回 nil，那一行不显示，宁可少写也不猜。
    private static func periodText(for product: Product) -> String? {
        guard let period = product.subscription?.subscriptionPeriod else { return nil }
        switch (period.unit, period.value) {
        case (.month, 1): return L10n.subPeriodMonthly
        case (.year, 1):  return L10n.subPeriodYearly
        default:          return nil
        }
    }

    // MARK: - 披露

    /// 审核条款 3.1.2 对自动续期订阅的要求：写清何时扣款、怎么取消，并提供**可用的**
    /// 使用条款与隐私政策链接。这几行不是装饰，删掉会直接被拒。
    private var disclosureSection: some View {
        VStack(spacing: 10) {
            Text(L10n.subAutoRenew)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 20) {
                Link(L10n.subTermsOfUse, destination: Self.termsOfUseURL)
                Link(L10n.subPrivacyPolicy, destination: Self.privacyPolicyURL)
            }
            .font(.caption)
        }
        .padding(.horizontal)
    }
}
