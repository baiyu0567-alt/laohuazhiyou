import StoreKit
import SwiftUI
import Combine
import OSLog

/// 订阅状态与免费额度。**App 级唯一实例**（`shared`），不是付费墙的私有状态。
///
/// ## 为什么必须是单例、必须住在 App 层
///
/// 它原先只活在 `PaywallView` 里（`@StateObject`），于是付费墙一关，Pro 状态就没了，
/// App 其他地方**读不到**用户是不是 Pro——`isProSubscriber` 全仓库只有它自己写、自己读。
/// 那样「订阅」在 App 里等于没有下文：买了也用不上。
///
/// 而它**不能**放进 `ContentView`：`PresbyFriendApp` 上挂着 `.id(languageManager.current)`，
/// 改一次语言会连同 `ContentView` 持有的所有 `@StateObject` 一起销毁重建，Pro 状态会被
/// 顺手清掉。这和 `router` 当初被提到 App 层的理由是同一条（见 `PresbyFriendApp` 里那段注释）。
///
/// ## 隔离必须写死，不能靠默认值
///
/// 本文件在 `PresbyFriend/` 目录下，**同时编进 app 和 shareextention 两个 target**，
/// 而两个 target 的默认 actor 隔离**不一样**（app 是 MainActor，扩展是 nonisolated；
/// 该设置不在 `project.pbxproj` 里，读源码看不出来）。所以这里显式标 `@MainActor`，
/// 让两个 target 的行为**一致**，而不是一边对一边错、编译器只给个警告。
@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    /// 用户当前是不是有效订阅。**由 `Transaction.currentEntitlements` 决定**，
    /// 启动时算一次、`Transaction.updates` 之后重算。
    @Published private(set) var isProSubscriber: Bool

    /// 权益有没有从 StoreKit 拿到过。见 `canUseToday` 里那段空窗说明。
    @Published private(set) var isEntitlementLoaded = false

    @Published private(set) var products: [Product] = []

    /// 商品列表**查过一次**了没有（无论查成什么样）。
    ///
    /// **没有它，`products.isEmpty` 一个值要同时表示三件事**：「还在查」「查过了，
    /// 一条都没有」「查询本身失败了」。而付费墙的首帧渲染发生在 `.task` 之前，于是
    /// 这三种情况用户**第一眼看到的都是那两张写死的兜底价签**（$2.99 / $19.99），
    /// 真商品查回来之后才被换掉——一次看得见的跳变，且「真没配」和「正在加载」
    /// 长得一模一样。
    ///
    /// 「查询失败」那一态由 `storeMessage` 另外分开（失败时会写 `L10n.storeError`），
    /// 所以这三态两两可分。
    @Published private(set) var isProductsLoaded = false

    /// 最近一次购买/恢复**要告诉用户的那句话**，已经本地化。nil = 没话可说。
    ///
    /// 为什么不是「错误原文」：原先这里是 `error.localizedDescription`，那串是**系统英文**
    /// （`The operation couldn't be completed. (StoreKit.StoreKitError error 2.)`）。把它直接
    /// 上屏，等于把「静默」修成了「当面说一句谁都看不懂的话」——本 App 只有 6 种语言，
    /// 而它哪一种都不是。所以：**屏上只放 `L10n` 里的句子，原文进日志**。
    ///
    /// 三件事都会往这里写：失败（`L10n.storeError`）、待批准（`L10n.purchasePending`）。
    /// **用户自己按取消不写**——那是他的动作，不是需要被告知的状态。
    @Published var storeMessage: String?

    /// 本文件同时编进 app 与 shareextention（见类文档），所以 subsystem 跟着 `Bundle.main`
    /// 走，不在扩展里冒充 App 的标识。与 `ReadTabView` 的写法一致。
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.presbyfriend",
        category: "subscription")

    private let productIDs = [
        "com.presbyfriend.pro.monthly",
        "com.presbyfriend.pro.yearly",
    ]
    private let freeLimitPerDay = 10
    private let defaults = UserDefaults.standard

    private static let isProCacheKey = "isProCached"
    private static let dailyUseCountKey = "dailyUseCount"
    private static let lastUseDateKey = "lastUseDate"

    private var isStarted = false
    private var updatesTask: Task<Void, Never>?

    private init() {
        // 先用上次落盘的结论顶上，等 `refreshEntitlements()` 回来再校正。
        // 缓存只是**离线兜底**，不是真相——真相永远以 StoreKit 为准，见 `refreshEntitlements`。
        isProSubscriber = defaults.bool(forKey: Self.isProCacheKey)
    }

    // MARK: - 生命周期

    /// 挂上权益监听并做首次校验。**幂等**：`.id` 重建视图树时 `onAppear` 会再响一次，
    /// 重复挂 `Transaction.updates` 会收到重复回调。
    func start() {
        guard !isStarted else { return }
        isStarted = true

        // 必须在启动早期就挂上：续订、家庭共享、Ask to Buy 批准、在别的设备上购买，
        // 都只经这条流回来，晚挂就永远收不到。
        // `StoreKit.Transaction` 必须写全：SwiftUI 也有一个 `Transaction`
        // （动画那套），本文件两个模块都 import，不写全就是歧义。
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.handle(update: result)
            }
        }

        Task { await refreshEntitlements() }
    }

    // MARK: - 商品

    func loadProducts() async {
        // 重新查就先把这个标志放下，界面该显示「正在查」而不是上一次的结果。
        // `products` **不清**：这一趟查失败时，上一次那份仍然是有效的、可购买的，
        // 清了等于把用户手里的东西收走。
        isProductsLoaded = false
        do {
            // **按 `productIDs` 的顺序重排**：`Product.products(for:)` 不保证返回顺序，
            // 直接渲染的话付费墙上的月付/年付可能这次在上、下次在下——同一屏内容换位置，
            // 对需要靠位置记东西的用户是实打实的干扰。
            let loaded = try await Product.products(for: productIDs)
            // ⚠️ **空列表不抛错，所以下面那个 `catch` 抓不到它**——而这恰恰是 scheme 的
            // StoreKit 配置没被应用时的表现：查询「成功」返回空数组，没有异常、没有日志、
            // `storeMessage` 保持 nil，付费墙静静退到 fallback 价签，用户点下去什么都不会发生。
            //
            // 这与 Android 侧那个最隐蔽的坑是**同一个故障模式**：「缺 BILLING 权限时
            // `queryProductDetailsAsync` 返回空列表，而 `responseCode` 仍然是 OK」。
            // 两边的教训也一样——**只看有没有报错是看不出来的，必须单独看列表长度**。
            // 所以这里必须记一笔，它是唯一能把「还没配商品」和「配置没生效」分开的线索。
            if loaded.isEmpty {
                // 先取成局部常量再插值：`Logger` 的插值参数是 `@autoclosure`，
                // 在里面直接引用实例属性会要求显式 `self.`。
                let requested = productIDs.joined(separator: ", ")
                Self.logger.error(
                    "商品列表为空且未抛错 —— 优先怀疑 scheme 的 StoreKit 配置没被应用（productIDs: \(requested, privacy: .public)）")
            }
            products = productIDs.compactMap { id in loaded.first { $0.id == id } }
        } catch {
            Self.logger.error("载入商品失败: \(error, privacy: .public)")
            storeMessage = L10n.storeError
        }
        // 两条路都要置：这个标志说的是「查过一次了」，不是「查成功了」。
        // 它只置于失败分支，界面就会永远停在转圈上。
        isProductsLoaded = true
    }

    // MARK: - 购买 / 恢复

    /// 返回 `true` 表示**现在已经是 Pro**（调用方据此决定关不关付费墙）。
    /// 「待批准」「失败」「用户取消」都返回 `false`，但三者对用户说的话**不一样**，
    /// 区别留在 `storeMessage` 里。
    func purchase(_ product: Product) async -> Bool {
        storeMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    // 没通过验签的交易不能当权益用，也不能 finish（Apple 的样例就是
                    // 把它丢在 `catch` 里等下次重投）。
                    Self.logger.error("交易未通过验签: \(product.id, privacy: .public)")
                    storeMessage = L10n.storeError
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                return isProSubscriber

            case .userCancelled:
                // 用户自己按了取消，不是错误，不该弹提示。
                return false

            case .pending:
                // Ask to Buy 等家长批准：结果会经 `Transaction.updates` 回来，
                // 这次调用拿不到。**不能不说**——什么都不显示，用户看到的就是
                // 「点了没反应」，而他的钱其实已经挂在那儿了。
                storeMessage = L10n.purchasePending
                return false

            @unknown default:
                return false
            }
        } catch {
            Self.logger.error("购买失败 \(product.id, privacy: .public): \(error, privacy: .public)")
            storeMessage = L10n.storeError
            return false
        }
    }

    /// 返回 `true` 表示恢复之后确实是 Pro。与 `purchase` 同理：
    /// 「本来就没有买过」和「查询本身失败了」是两件事，前者由调用方报
    /// `restoreNoPurchases`，后者已经在 `storeMessage` 里。
    @discardableResult
    func restorePurchases() async -> Bool {
        storeMessage = nil
        do {
            // 让 StoreKit 去 Apple 那边对一次账，而不是只读本地回执。
            try await AppStore.sync()
        } catch {
            // 用户取消同步不是失败——他去别处转了一圈又回来，不该被报错。
            if case StoreKitError.userCancelled = error {
                await refreshEntitlements()
                return isProSubscriber
            }
            Self.logger.error("恢复购买同步失败: \(error, privacy: .public)")
            storeMessage = L10n.storeError
            // 同步失败也往下走：本地权益仍然值得读一次，能恢复多少算多少。
        }
        await refreshEntitlements()
        return isProSubscriber
    }

    // MARK: - 权益

    /// **这是唯一的真相来源。** 每次调用都要能算出 `true`、也要能算出 `false`——
    /// Android 那边是「一旦 true 就永不写回 false」，退款或订阅过期之后用户还是 Pro，
    /// 那是个缺陷，不要照抄。
    func refreshEntitlements() async {
        var entitled = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard productIDs.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            // 自动续期订阅：`currentEntitlements` 本来就不含已过期的，这里再显式挡一道，
            // 免得将来换了 API 语义悄悄变宽。
            if let expiration = transaction.expirationDate, expiration <= Date() { continue }
            entitled = true
        }
        apply(entitled: entitled)
    }

    private func handle(update result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else {
            // 验签失败的交易不授予权益、也不 finish。只把原因留下来。
            if case .unverified(_, let error) = result {
                Self.logger.error("交易更新未通过验签: \(error, privacy: .public)")
                storeMessage = L10n.storeError
            }
            return
        }
        // **不属于本 App 的交易不要 finish。** 今天这条不可能触发（只有订阅两个商品，
        // 而它们全归我们管），但 `finish()` 是不可逆的「已发货」回执：将来加一个消耗型
        // 商品而这里照单全收，就会出现「没发货却已签收」，而且没有任何痕迹可查。
        // 判据与 `refreshEntitlements()` 里那一句保持一致。
        guard productIDs.contains(transaction.productID) else { return }
        await transaction.finish()
        await refreshEntitlements()
    }

    private func apply(entitled: Bool) {
        isProSubscriber = entitled
        isEntitlementLoaded = true
        defaults.set(entitled, forKey: Self.isProCacheKey)
    }

    // MARK: - 免费额度

    /// 今天还能不能用。**只读，不改任何状态**——计数由 `recordUse()` 单独做，
    /// 这样「查了但没用」不会白白扣掉一次。
    var canUseToday: Bool {
        if isProSubscriber { return true }

        // ⚠️ **空窗放行**：`refreshEntitlements()` 是异步的，首次启动有几十到几百毫秒
        // 拿不到结论。这段窗口里若按「不是 Pro」处理，会把**付费用户**拦下来——
        // 那是比多放一次更坏的错。所以没加载完一律放行。
        if !isEntitlementLoaded { return true }

        return dailyUseCountToday < freeLimitPerDay
    }

    /// 今天已经用掉的次数。跨天按**本地时区**算。
    ///
    /// 有意与 Android 不一致：那边用 `millis / 86400000`（UTC 日界），对 UTC+8 的用户
    /// 等于**早上 8 点换天**。这里沿用本地日历。
    var dailyUseCountToday: Int {
        let last = defaults.object(forKey: Self.lastUseDateKey) as? Date ?? .distantPast
        guard Calendar.current.isDate(last, inSameDayAs: Date()) else { return 0 }
        return defaults.integer(forKey: Self.dailyUseCountKey)
    }

    /// 记一次使用。跨天则从 1 开始，否则累加。
    ///
    /// 调用点是「**真正呈现给用户**」的那一刻，不是「用户点了按钮」的那一刻——
    /// 被后来者顶掉、最终没呈现的那次不该扣（见 `ReaderLaunchCoordinator` 两个入口）。
    func recordUse() {
        let now = Date()
        let last = defaults.object(forKey: Self.lastUseDateKey) as? Date ?? .distantPast
        let sameDay = Calendar.current.isDate(last, inSameDayAs: now)
        let count = sameDay ? defaults.integer(forKey: Self.dailyUseCountKey) + 1 : 1
        defaults.set(count, forKey: Self.dailyUseCountKey)
        defaults.set(now, forKey: Self.lastUseDateKey)
    }
}
