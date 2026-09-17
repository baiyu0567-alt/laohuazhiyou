import SwiftUI
import Combine
import OSLog

// MARK: - Siri Shortcut Activity Types

enum SiriActivity: String {
    case openMagnifier = "com.presbyfriend.open-magnifier"

    var title: String {
        switch self {
        case .openMagnifier: return L10n.magnifierTab
        }
    }

    func donate() {
        let activity = NSUserActivity(activityType: rawValue)
        activity.title = title
        activity.isEligibleForPrediction = true
        activity.isEligibleForSearch = true
        activity.persistentIdentifier = rawValue
        activity.becomeCurrent()
    }
}

// MARK: - App

@main
struct PresbyFriendApp: App {
    @StateObject private var settings = SettingsModel()
    @StateObject private var languageManager = LanguageManager.shared

    /// 「用户停在哪个 tab」。**它必须住在 `.id` 外面。**
    ///
    /// 下面 `ContentView` 挂着 `.id(languageManager.current)`——那道 `.id` 的用途是
    /// 改语言后强制重建视图树（`LanguageAwareBundle` 是在查找的那一刻读
    /// `LanguageManager.shared.current`，不重建就换不掉已算出的文案）。但 `.id` 换值的
    /// 代价是整个 `ContentView` 连同它持有的 `@StateObject` 一起销毁重造，而 `router`
    /// 原先正是其中之一：改一次语言，`selectedTab` 就被按回默认值 `0`，
    /// 用户在设置页选完语言，下一帧就站在放大镜页上了。
    ///
    /// 提到这里之后，`router` 活在 `.id` 之外，语言重建不再动它。
    @StateObject private var router = TabRouter()

    var body: some Scene {
        WindowGroup {
            ContentView(router: router)
                .environmentObject(settings)
                .id(languageManager.current)  // Force reload on language change
                .onAppear {
                    Bundle.enableLanguageSwitching()
                    settings.load()
                    languageManager.current = settings.language
                }
                .onOpenURL { settings.pendingURL = $0 }
                .onChange(of: settings.language) { lang in
                    languageManager.current = lang
                }
        }
    }
}

// MARK: - Router

final class TabRouter: ObservableObject {
    @Published var selectedTab = 0
}

// MARK: - Content View (3 tabs: Magnifier + Read + Settings)

struct ContentView: View {
    @EnvironmentObject var settings: SettingsModel
    /// 由 `PresbyFriendApp` 持有并从外面传进来——**不在这里建**，理由是那道
    /// `.id(languageManager.current)` 会把 `ContentView` 整个重建掉（见
    /// `PresbyFriendApp` 里 `router` 的注释）。
    @ObservedObject var router: TabRouter
    @StateObject private var coordinator = ReaderLaunchCoordinator()

    /// 识别语言偏好**已经生效**的那一个值。
    ///
    /// 用来区分两件长得一样的事：**用户在设置页改了选择**，和**冷启动时
    /// `settings.load()` 把存储值读出来**。后者只要与默认值 `.followSystem` 不同，
    /// `settings.recognitionLanguage` 的 `.onChange` 就会真触发一次——那是读设置，
    /// 不是用户操作，预热归 `.task` 里那次。真正需要补一次预热的只有用户在设置页改了选择。
    ///
    /// 不区分的话，每次冷启动会多打一次 `prewarm()`——两份数组逐字相同（都出自
    /// `load()` 之后的 `settings.recognitionLanguage`），而 `prewarm()` 本身没有幂等闸
    /// （见它的注释），这次调用落在预热还在途的窗口里，拦不住。代价只是第二次
    /// `recognize` 排在串行 `queue` 上、模型已热之后那实测的 0.1–0.35s（见
    /// `TextRecognitionService.prewarm()` 的注释），不是再准备一遍模型：
    /// 这道闸省掉的是一次**无谓的调用**。
    ///
    /// 改动前这里还有第二条路（存储为空而设备语言是中文时 `initialDefault` 会预选出中文，
    /// 与当时的默认值 `.followApp` 不同）。现在默认值本身就是「跟随系统」，那条路没有了：
    /// 存储为空 ⇒ `load()` 得到 `.followSystem` ⇒ 与默认值相同 ⇒ 不触发。**这道闸因此
    /// 比改动前更简单，而不是更复杂。**
    @State private var appliedRecognitionLanguage: RecognitionLanguage?

    /// URL 分享进来、但没能得到可读正文时，给用户一个看得见的交代。
    ///
    /// 以前这里什么都不发生：`if text.count > 50` 没有 else，提取失败也只写日志。
    /// 同一个条件在分享扩展里是报错的（`ShareView.swift:173-177`，同一个 50 字阈值、
    /// 同一个键），App 里却是静默——用户主动分享后毫无反应，等于「App 坏了」。
    @State private var showingURLExtractError = false

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.presbyfriend",
        category: "url-extract")

    var body: some View {
        ZStack {
            TabView(selection: $router.selectedTab) {
                NavigationStack {
                    MagnifierTab(
                        onTextDetected: { text in coordinator.open(text: text) },
                        settings: settings
                    )
                }
                .tabItem { Label(L10n.magnifierTab, systemImage: "magnifyingglass") }
                .tag(0)

                NavigationStack {
                    ReadTabView()
                }
                .tabItem { Label(L10n.readTab, systemImage: "text.viewfinder") }
                .tag(1)

                // SettingsView 自带 NavigationStack，这里不要再包一层
                SettingsView()
                    .tabItem { Label(L10n.settingsTab, systemImage: "gearshape") }
                    .tag(2)
            }
            .onContinueUserActivity(SiriActivity.openMagnifier.rawValue) { _ in
                router.selectedTab = 0
            }

            if coordinator.isPreparing {
                Color.black.opacity(0.4).ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                    Text(L10n.ocrPreparing)
                        .font(.title3)
                        .foregroundColor(.white)
                    // 取消出口。首用 OCR 实测 28–34s（见 TextRecognitionService.prewarm
                    // 的注释），不能把老花眼用户困在一块完全无响应的半黑屏幕里。
                    // 取消走 close()：它会自增 generation，在途的那次 OCR 回来时
                    // 落在 open(image:) 的 guard 上被丢掉，不会再弹出阅读页。
                    // 字号与点击区都做大——小号暗淡的「×」正是这里要避免的东西。
                    // frame 放在 Button 的 label 内部，这样 .borderedProminent 的底色
                    // 本身就是 180×64，点击区不留任何歧义。
                    Button(action: { coordinator.close() }) {
                        Text(L10n.close)
                            .font(.title2)
                            .frame(minWidth: 180, minHeight: 64)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(28)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .zIndex(200)
            }

            if coordinator.isPresenting {
                NavigationStack {
                    readerContent
                }
                .zIndex(100)
            }
        }
        .alert(L10n.urlExtractFail, isPresented: $showingURLExtractError) {
            Button(L10n.close, role: .cancel) {}
        }
        .environmentObject(coordinator)
        .task {
            // 启动时后台准备识别模型，避免第一次按快门等 28s。
            //
            // 先自己把存储的设置读进来，**不再依赖** App 层 `.onAppear` 里那次 `load()`
            // 先于本 `.task` 到达——SwiftUI 不保证这个顺序，而押在它上面的后果是冷启动
            // 预热两遍（`.task` 热默认那组，随后的 onChange 再热存储那组，两份
            // 不同的数组，`prewarm()` 没有幂等闸，两次都会真跑）。
            // `load()` 幂等且便宜（只读 UserDefaults 并给 @Published 赋值，见
            // SettingsModel.swift:20-29），`ShareView` 也已经连着调过两次，所以这里先读
            // 一次是安全的：读进来之后记下的就是存储值，下面那个 `.onChange` 会被闸挡掉。
            // `load()` 若真的发布了变化，两种落点都只预热一遍：
            //   - `.onChange` 在本 `.task` 之前/期间到达：`appliedRecognitionLanguage`
            //     还是 nil，走 nil 分支只记录不预热，预热由下面这次负责；
            //   - `.onChange` 在本 `.task` 之后到达：`applied` 已等于新值，被 `!= newValue` 挡掉。
            settings.load()
            applyRecognitionLanguages()
            appliedRecognitionLanguage = settings.recognitionLanguage
            coordinator.prewarm()
        }
        .onChange(of: settings.recognitionLanguage) { newValue in
            // 设置页可以在运行中改语言（这是 Task 10 新开的路径，在此之前只能重启才生效）。
            // 换语言必须**先于**预热：`prewarm()` 最终走到 `recognize`，读的是当时生效的
            // `languages`；顺序反了就是拿旧语言去预热，等于没热。
            applyRecognitionLanguages()
            // 冷启动那次 `load()` 读出存储值时也会走到这里（存储值与默认值 `.followSystem`
            // 不同才会），但那是读设置、不是用户操作，预热归上面的 `.task`：`.task` 会先跑完
            // `load()` 并把结果记进 `appliedRecognitionLanguage`，于是无论这个回调落在它
            // 之前还是之后，下面那道闸都会挡掉（落在之前 → `applied` 还是 nil，走 nil 分支
            // 只记录；落在之后 → 已相等）。
            // 所以这里只对运行中的真实变更补一次预热，且每次变更恰好一次：判的是
            // 「和已经生效的值不同」，用户在两个选项间来回切，每一次都会预热。
            if let applied = appliedRecognitionLanguage, applied != newValue {
                coordinator.prewarm()
            }
            appliedRecognitionLanguage = newValue
        }
        .onChange(of: settings.pendingURL) { url in
            guard let url else { return }
            settings.pendingURL = nil
            Task {
                do {
                    let extractor = URLExtractor()
                    let text = try await extractor.extract(from: url.absoluteString)
                    if text.count > 50 {
                        coordinator.open(text: text)
                    } else {
                        // 提取成功但正文太短：扩展在同样条件下报的是同一个键，App 不能再静默。
                        showingURLExtractError = true
                    }
                } catch {
                    Self.logger.error("URL extraction failed for \(url.absoluteString, privacy: .public): \(String(describing: error))")
                    // 抛错同样是「用户分享了、什么都没发生」。
                    //
                    // **但取消不是失败。** 两个合取项**今天都不会触发**，留它们是为了防两种
                    // **不同的未来**——都不能因为「在这里看起来没用」而删掉：
                    //   - `error is CancellationError`：防的是**任务的取消位没被置上、却抛出了
                    //     `CancellationError`** 的情形——嵌套任务，或某个依赖用「抛错」而不是用
                    //     「标志位」来报告取消。它**不**负责 `Task.checkCancellation()`：那个 API
                    //     只在当前任务已取消时才抛，也就是**恰好** `Task.isCancelled` 为真的同一
                    //     条件，两者会一起变假，对那条路它是多余的——**不是「到时候就轮到它起作用」**。
                    //     （今天它空转的理由：`extract` 唯一的挂起点是 `URLExtractor.swift:23` 的
                    //     `URLSession.shared.data(from:)`，全文件没有一处 `Task.checkCancellation()`；
                    //     而 URLSession 报取消用的是 `URLError(.cancelled)`（NSURLError −999），
                    //     不是 `CancellationError`。）
                    //   - `!Task.isCancelled`：防的是**任务真的被取消**——它读的是当前任务的取消位，
                    //     与抛出来的具体错误类型无关。今天它**同样从不触发**：没有任何东西持有这个
                    //     非结构化 `Task`（`:196`）的句柄，它不会被取消，所以这一半恒为真，
                    //     「它有没有用」**无法靠阅读观察出来**（读代码只会看到恒为真）。一旦日后
                    //     有改动让这个任务变得可取消，删掉它就等于把这道守卫要防的那个行为重新
                    //     装回去（任务被取消 → 弹一个「提取失败」，而用户并没有失败）。
                    if !(error is CancellationError) && !Task.isCancelled {
                        showingURLExtractError = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var readerContent: some View {
        if let text = coordinator.text {
            ReaderView(text: text, paragraphs: nil,
                       languageHint: coordinator.languageHint,
                       onClose: { coordinator.close() })
        } else if let source = coordinator.fallbackImage {
            ZStack(alignment: .top) {
                ZoomableImageView(image: source.uiImage)
                    .ignoresSafeArea()
                VStack {
                    // 识别失败要说「读不出来」，不能拿「没有文字」搪塞——两者都走
                    // 这张兜底原图，只有文案能区分。
                    Text(coordinator.recognitionFailed ? L10n.ocrFail : L10n.ocrNoText)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding()
                    // 语言提示接在兜底文案下面。这条分支和提示并不互斥——恰恰相反，
                    // 「一个字都没认出来」正是提示最该出现的场合之一（`looksWeak` 的
                    // 第一个条件就是 0 块）。反过来，`recognitionFailed` 为真时
                    // `languageHint` 必为 nil（见 `hint(for:failed:)`），所以这里
                    // 不会出现「读不出来 + 可能是语言不对」叠在一起自相矛盾。
                    if let hint = coordinator.languageHint {
                        languageHintCard(hint)
                    }
                    Spacer()
                }
                VStack {
                    Spacer()
                    Button(L10n.close) { coordinator.close() }
                        .font(.title2)
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 32)
                }
            }
        } else {
            // `isPresenting` 为真、两条内容路径却都为空：不能留一块没有出口的全屏空白——
            // 阅读页是 ZStack 里盖住 TabView 的视图，不是 sheet，没有下滑关闭的手势，
            // 这个 App 的用户没有别的方式退出。
            //
            // 今天渲染不到：`isPresenting` 只在 `open(text:)` / `open(image:)` 里置为 true，
            // 而这两处都在同一次「先填内容、后置标志」的同步执行里完成。两条路径都会
            // **瞬时**经过这个状态——`open(image:)` 的兜底分支（`text = nil` 执行完时
            // `fallbackImage` 还没被赋值）和 `open(text:)`（`fallbackImage = nil` 执行完时
            // `self.text` 还没被赋值）。
            //
            // 两条路径的可达性都**没有得到支持**，所以这条兜底是防御性的。
            //
            // 这里曾经写着「够得着的是后者」——阅读页已经开着时从外部进来一个 URL，走
            // `onOpenURL` → `settings.pendingURL` → 下面那个 `.onChange` → `open(text:)`，
            // 此时 `isPresenting` 已经是 true。**这个说法站不住**：
            // `settings.pendingURL` 全树只有一个写者，就是 `:43` 的 `onOpenURL`；而 iOS 能把
            // URL **送进 `onOpenURL`** 的几条路，本 App **一条都不具备**——下面是**逐条排除**，
            // 不是只看了两个键就下结论。（**这几条只排除「通向 `onOpenURL` 的路」**，
            // 不等于「iOS 能给 App 送 URL 的全部方式」——见下面 Siri/活动 那一段。）
            //   - **URL scheme**：`CFBundleURLTypes` 在 `project.pbxproj` 里不存在，在**构建
            //     产物**的 `PresbyFriend.app/Info.plist` 上实测也是 "Does Not Exist"；
            //   - **document type**：`CFBundleDocumentTypes` 同上，两处都没有；
            //   - **universal link**：需要 `com.apple.developer.associated-domains` 权限，
            //     而两个 entitlements 文件（app 的 `PresbyFriend/PresbyFriend.entitlements`、
            //     扩展的 `shareextention/shareextention.entitlements`）逐个打开看过，
            //     里面都**只有** `com.apple.security.application-groups` 这一个键；
            //   - **widget 的 `widgetURL`**：本工程只有两个 target——app
            //     （`com.apple.product-type.application`）与分享扩展
            //     （`com.apple.product-type.app-extension`），**没有 widget extension**，
            //     也没有任何 widget 源文件（`find ios -iname '*widget*'` 为空）。
            //
            // 所以 `onOpenURL` 没有入口。**注意别把理由写窄**：scheme 与 document type 只是
            // 这几条路里的两条，缺少它们本身并不等于「iOS 打不开」——是上面四条合起来才成立的。
            //
            // 但**不能**由此说成「不可达」：本 App 确实还有一条 Siri/活动 面——app target 的
            // 构建设置声明了 `INFOPLIST_KEY_NSUserActivityTypes`（`project.pbxproj:364/:401`，
            // 两个活动类型），`:114` 也挂了 `.onContinueUserActivity`。那条路能不能把 URL
            // 送进来，**没有设备无法断定**。可以确定的只有：`:114` 的处理闭包只切 tab
            // （`router.selectedTab = 0`），从不写 `pendingURL`，所以它不构成 `pendingURL`
            // 的来源。（另一处实测：该键并未出现在构建产物的 Info.plist 里。）
            //
            // 前者（阅读页开着时调起 `open(image:)`）则被全屏遮罩挡着（放大镜快门和读取 tab
            // 都在它下面）。
            //
            // 两条之所以都看不见，只是因为主 actor 上两条相邻语句之间插不进一次渲染
            // ——这个性质没有任何东西在保证，中间多一个 `await` 就会漏出来。
            // 代价是十行兜底，收益是永远不会把用户困在黑屏上。
            ZStack {
                Color.black.ignoresSafeArea()
                VStack {
                    Spacer()
                    Button(L10n.close) { coordinator.close() }
                        .font(.title2)
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 32)
                }
            }
        }
    }

    /// 识别语言可能选错了的提示——兜底原图那一支用的版本。
    ///
    /// 和 `ReaderView.languageHintCard` 是**两份**，不是疏忽：那一支画在阅读主题的底色上、
    /// 用主题正文色的淡色，这一支画在照片上、必须用材质才在任意照片上都读得清。
    /// 文案只有一份，在 `L10n` 里。
    private func languageHintCard(_ hint: LanguageHint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.ocrHintLanguageTitle)
                .font(.headline)
            // 正文和 `ReaderView` 那张卡片是同一份（`languageHintBody`）。两张卡片
            // 只有底色/版式不同，说法必须一致——见那个函数的文件头。
            Text(languageHintBody(hint))
                .font(.subheadline)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    /// 识别语言在这里解析：读设备语言 + 用户在设置页的选择，交给
    /// `RecognitionLanguage` 构造出 Vision 的语言数组。
    ///
    /// 设备语言必须读 `Locale.preferredLanguages`，**不能用 `Locale.current`**：后者
    /// 按本 App 的本地化过滤过——本 App 只出 en/de/fr/es/it/pt（六份 `*.lproj` +
    /// `developmentRegion = en`，且没有 `CFBundleLocalizations`），所以在**中文系统**的
    /// 设备上它返回 `en`。已在 booted 模拟器上对本 App 实测：`-AppleLanguages (zh-Hans)`
    /// 启动时 `Locale.current.languageCode = en`（identifier `en_CN`，
    /// `preferredLocalizations = [en]`），而 `Locale.preferredLanguages[0] = "zh-Hans"`。
    ///
    /// 读的是**实时值**，不是启动时缓存的一份：跟随系统要真的跟随，就不能在别处算一次冻住。
    /// 已知边界：系统语言在 App 运行中改变不会触发这里重算（没有任何东西在监听它），
    /// 但 iOS 改系统语言通常会把 App 重启，那条路会重新走到这里。
    private func applyRecognitionLanguages() {
        let deviceLanguageCode = Locale.preferredLanguages.first
        let supported = OCRSupportedLanguageCodes.all
        coordinator.updateLanguages(
            RecognitionLanguage.visionLanguages(deviceLanguageCode: deviceLanguageCode,
                                                preference: settings.recognitionLanguage,
                                                supported: supported),
            // 同一个 `supported`、同一个设备语言码算出来的「系统语言那一档」——
            // 阅读页据此判断「实际用的 ≠ 系统语言」，两者必须同源。
            systemCode: RecognitionLanguage.systemLanguageCode(
                deviceLanguageCode: deviceLanguageCode,
                supported: supported))
    }
}

// MARK: - Magnifier Tab (wraps MagnifierView + handles simulator)

struct MagnifierTab: View {
    /// 由 `ContentView` 的 `ZStack` 上挂的 `.environmentObject(coordinator)` 提供。
    @EnvironmentObject private var coordinator: ReaderLaunchCoordinator
    /// 只有模拟器分支那条「See how reading works」按钮读它。真机上放大镜**没有**实时
    /// 文字层了（理由见 `MagnifierView` 里预览那段注释），所以真机构建里它无从被读——
    /// 留着是因为模拟器构建仍然需要它，而且这是 `ContentView` 交下来的既有接口。
    let onTextDetected: (String) -> Void
    let settings: SettingsModel
    @State private var showMagnifier = false
    @State private var showReader = false

    var body: some View {
        Group {
            #if targetEnvironment(simulator)
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
                Text(L10n.cameraError)
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Text(L10n.accessibilityHint)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("See how reading works") {
                    onTextDetected("This is PresbyFriend reading mode.\n\nUse the Aa button to adjust font size, theme, line height and letter spacing.\n\nTap the play button above to hear it read aloud.")
                }
                .buttonStyle(.borderedProminent)
                .tint(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle(L10n.appName)
            #else
            MagnifierView(
                onCapture: { source in
                    // `onCapture` 是同步回调，`open(image:)` 是 async，所以要起一个 Task。
                    // 这个 Task 是不受结构化管理的一次性任务，没有任何人持有它的句柄。
                    Task { await coordinator.open(image: source) }
                }
            )
            #endif
        }
    }
}
