import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @StateObject private var vm = SettingsViewModel()
    @State private var showResetAlert = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.defaultFont) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(Int(vm.fontSize))px")
                                .font(.system(size: CGFloat(vm.fontSize)))
                                .foregroundColor(.primary)
                            Spacer()
                            Button { vm.fontSize = max(24, vm.fontSize - 4) } label: {
                                Image(systemName: "minus.circle.fill").font(.title2)
                            }
                            Slider(value: $vm.fontSize, in: 24...72, step: 4)
                                .frame(width: 120)
                            Button { vm.fontSize = min(72, vm.fontSize + 4) } label: {
                                Image(systemName: "plus.circle.fill").font(.title2)
                            }
                        }
                    }
                }

                Section(L10n.defaultTheme) {
                    HStack(spacing: 16) {
                        ForEach(ReadingTheme.allCases, id: \.self) { theme in
                            VStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(theme.backgroundColor)
                                    .frame(height: 44)
                                    .overlay {
                                        if vm.theme == theme {
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(theme.accentColor, lineWidth: 3)
                                        }
                                    }
                                Text(theme.displayName)
                                    .font(.caption)
                            }
                            .onTapGesture { vm.theme = theme }
                        }
                    }
                }

                Section {
                    Toggle(L10n.readingRuler, isOn: $vm.rulerEnabled)
                } footer: {
                    Text(L10n.rulerDescription)
                }

                Section(L10n.languageLabel) {
                    Picker(L10n.languageLabel, selection: $vm.selectedLanguage) {
                        ForEach(vm.availableLanguages, id: \.code) { lang in
                            Text(lang.name).tag(lang.code)
                        }
                    }
                }

                Section {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack {
                            Image(systemName: "crown.fill").foregroundColor(.orange)
                            Text(L10n.upgradePro)
                        }
                    }
                }

                Section(L10n.dataManagement) {
                    Button(L10n.resetSettings, role: .destructive) {
                        showResetAlert = true
                    }
                }

                Section {
                    Text(L10n.versionFooter)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .navigationTitle(L10n.settingsTab)
            .alert(L10n.resetConfirm, isPresented: $showResetAlert) {
                Button("Cancel", role: .cancel) {}
                Button(L10n.resetSettings, role: .destructive) {
                    settings.reset()
                    vm.load(from: settings)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
        .onAppear { vm.load(from: settings) }
        .onDisappear { vm.save(to: settings) }
    }
}
