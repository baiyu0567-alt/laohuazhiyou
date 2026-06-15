import SwiftUI

@main
struct PresbyFriendApp: App {
    @StateObject private var settings = SettingsModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .onAppear {
                    settings.load()
                }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        TabView {
            MagnifierView()
                .tabItem {
                    Label(L10n.magnifierTab, systemImage: "magnifyingglass")
                }

            SettingsView()
                .tabItem {
                    Label(L10n.settingsTab, systemImage: "gearshape")
                }
        }
    }
}
