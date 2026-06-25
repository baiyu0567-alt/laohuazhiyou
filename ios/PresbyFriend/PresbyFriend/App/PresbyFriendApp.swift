import SwiftUI
import Combine

// MARK: - Siri Shortcut Activity Types

enum SiriActivity: String {
    case openMagnifier = "com.presbyfriend.open-magnifier"
    case readClipboard = "com.presbyfriend.read-clipboard"

    var title: String {
        switch self {
        case .openMagnifier: return L10n.magnifierTab
        case .readClipboard: return L10n.readAloud
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
                .onChange(of: settings.language) { _, lang in
                    languageManager.current = lang
                }
        }
    }
}

// MARK: - Router

final class TabRouter: ObservableObject {
    @Published var selectedTab = 0
}

// MARK: - Content View (2 tabs: Magnifier + Settings)

struct ContentView: View {
    @EnvironmentObject var settings: SettingsModel
    @StateObject private var router = TabRouter()

    @State private var showReader = false
    @State private var readerText: String?
    @State private var readerParagraphs: [String]?
    @State private var lastClipboardText = ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            TabView(selection: $router.selectedTab) {
                NavigationStack {
                    MagnifierTab(
                        onTextDetected: { text in
                            readerText = text
                            readerParagraphs = nil
                            showReader = true
                        },
                        settings: settings
                    )
                }
                .tabItem {
                    Image(systemName: "magnifyingglass")
                }
                .tag(0)

                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Image(systemName: "gearshape")
                }
                .tag(1)
            }
            .onContinueUserActivity(SiriActivity.openMagnifier.rawValue) { _ in
                router.selectedTab = 0
            }
            .onContinueUserActivity(SiriActivity.readClipboard.rawValue) { _ in
                router.selectedTab = 0
            }

            // Reader overlay — shown from clipboard or text detection
            if showReader, let text = readerText {
                NavigationStack {
                    ReaderView(text: text, paragraphs: readerParagraphs, onClose: {
                        showReader = false
                        readerText = nil
                    })
                }
                .zIndex(100)
            }
        }
        .onAppear { checkClipboard() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active  { checkClipboard() }
            if phase == .background { lastClipboardText = "" }
        }
        .onChange(of: settings.pendingURL) { _, url in
            guard let url else { return }
            settings.pendingURL = nil
            Task {
                do {
                    let extractor = URLExtractor()
                    let text = try await extractor.extract(from: url.absoluteString)
                    if text.count > 50 {
                        readerText = text
                        readerParagraphs = nil
                        showReader = true
                    }
                } catch {}
            }
        }
    }

    private func checkClipboard() {
        let text = UIPasteboard.general.string ?? ""
        guard !text.isEmpty, text != lastClipboardText else { return }
        lastClipboardText = text
        SiriActivity.readClipboard.donate()
        readerText = text
        readerParagraphs = nil
        showReader = true
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
                    onTextDetected("This is PresbyFriend reading mode.\n\nCopy any text from another app → open PresbyFriend → it appears here automatically.\n\nTap the play button above to hear it read aloud.\n\nUse the Aa button to adjust font size, theme, line height and letter spacing.")
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
