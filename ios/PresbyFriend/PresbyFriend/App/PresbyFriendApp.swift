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

    var body: some Scene {
        WindowGroup {
            ContentView()
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
    @StateObject private var router = TabRouter()
    @StateObject private var coordinator = ReaderLaunchCoordinator()

    /// 识别语言偏好**已经生效**的那一个值。
    ///
    /// 用来区分两件长得一样的事：**用户在设置页改了选择**，和**冷启动时
    /// `settings.load()` 把存下来的值读进来**——`load()` 会把默认值 `.system`
    /// 改成存储值，所以 `settings.recognitionLanguage` 的 `.onChange` 在冷启动
    /// 时确实会真触发一次。只有前者需要补一次预热；后者由 `.task` 里那次负责。
    /// 不区分就会每次冷启动预热两遍。
    @State private var appliedRecognitionLanguage: RecognitionLanguage?

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
        .environmentObject(coordinator)
        .task {
            // 启动时后台准备识别模型，避免第一次按快门等 28s。
            //
            // 「先记下已生效的值、再预热」这个顺序就是上面的闸成立的前提，而它押在一条
            // 看不见的假设上：`SettingsModel.load()`（在 `body` 的 `.onAppear` 里，先于本
            // `.task`）会把 `recognitionLanguage` 从 `@Published` 默认的 `.system` 改成存储
            // 值，所以冷启动时下面那个 `.onChange` 会真触发一次；这里记下的值正是它将要带来
            // 的新值，那次 onChange 因此不重复预热——冷启动只预热一遍。
            // 假设若不成立（`load()` 晚于本 `.task`），记下的会是默认值 `.system`，load 之后
            // 的 onChange 会再预热一次：结果仍然安全，用户选的模型照样是热的，只是白跑一遍。
            applyRecognitionLanguages()
            appliedRecognitionLanguage = settings.recognitionLanguage
            coordinator.prewarm()
        }
        .onChange(of: settings.recognitionLanguage) { newValue in
            // 设置页可以在运行中改语言（这是 Task 10 新开的路径，在此之前只能重启才生效）。
            // 换语言必须**先于**预热：`prewarm()` 最终走到 `recognize`，读的是当时生效的
            // `languages`；顺序反了就是拿旧语言去预热，等于没热。
            applyRecognitionLanguages()
            // 冷启动那次 `load()` 也会走到这里（`.system` → 存储值本身就是一次变化），
            // 那不是用户操作，预热归上面的 `.task`。只对运行中的真实变更补一次预热，
            // 且每次变更恰好一次：这里判的是「和已经生效的值不同」，用户在两个选项间
            // 来回切，每一次都会预热。
            if let applied = appliedRecognitionLanguage, applied != newValue {
                coordinator.prewarm()
            }
            appliedRecognitionLanguage = newValue
        }
        .onChange(of: settings.language) { _ in applyRecognitionLanguages() }
        .onChange(of: settings.pendingURL) { url in
            guard let url else { return }
            settings.pendingURL = nil
            Task {
                do {
                    let extractor = URLExtractor()
                    let text = try await extractor.extract(from: url.absoluteString)
                    if text.count > 50 {
                        coordinator.open(text: text)
                    }
                } catch {
                    Self.logger.error("URL extraction failed for \(url.absoluteString, privacy: .public): \(String(describing: error))")
                }
            }
        }
    }

    @ViewBuilder
    private var readerContent: some View {
        if let text = coordinator.text {
            ReaderView(text: text, paragraphs: nil, onClose: { coordinator.close() })
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
            // 其中**够得着的是后者**：阅读页已经开着时从外部进来一个 URL，走 `onOpenURL`
            // → `settings.pendingURL` → 下面那个 `.onChange` → `open(text:)`，此时
            // `isPresenting` 已经是 true。前者要在阅读页开着时调起 `open(image:)`，而那条路
            // 被全屏遮罩挡着（放大镜快门和读取 tab 都在它下面）。
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

    private func applyRecognitionLanguages() {
        coordinator.updateLanguages(
            RecognitionLanguage.visionLanguages(
                systemLanguageCode: Locale.current.language.languageCode?.identifier,
                preference: settings.recognitionLanguage))
    }
}

// MARK: - Magnifier Tab (wraps MagnifierView + handles simulator)

struct MagnifierTab: View {
    /// 由 `ContentView` 的 `ZStack` 上挂的 `.environmentObject(coordinator)` 提供。
    @EnvironmentObject private var coordinator: ReaderLaunchCoordinator
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
                onTextDetected: onTextDetected,
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
