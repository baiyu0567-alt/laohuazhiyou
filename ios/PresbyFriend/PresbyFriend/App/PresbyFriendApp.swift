import SwiftUI
import Combine

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

    @Environment(\.scenePhase) private var scenePhase

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
            applyRecognitionLanguages()
            coordinator.prewarm()
        }
        .onChange(of: settings.recognitionLanguage) { _ in applyRecognitionLanguages() }
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
                } catch {}
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
                    Text(L10n.ocrNoText)
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
            MagnifierView(onTextDetected: onTextDetected)
            #endif
        }
    }
}
