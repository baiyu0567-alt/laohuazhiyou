import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @StateObject private var vm = SettingsViewModel()
    @State private var showResetAlert = false
    @State private var showPaywall = false

    private let labelFont = Font.title3
    private let bodyFont = Font.body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n.defaultFont)
                        .font(labelFont)
                } header: {
                    EmptyView()
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(Int(vm.fontSize))px")
                            .font(.system(size: CGFloat(vm.fontSize)))
                            .foregroundColor(.primary)
                        Spacer()
                        Button { vm.fontSize = max(24, vm.fontSize - 4) } label: {
                            Image(systemName: "minus.circle.fill").font(.system(size: 36))
                        }
                        Slider(value: $vm.fontSize, in: 24...72, step: 4)
                            .frame(width: 120)
                        Button { vm.fontSize = min(72, vm.fontSize + 4) } label: {
                            Image(systemName: "plus.circle.fill").font(.system(size: 36))
                        }
                    }
                }
                .padding(.vertical, 8)

                Section {
                    Text(L10n.defaultTheme)
                        .font(labelFont)
                }

                Section {
                    HStack(spacing: 20) {
                        ForEach(ReadingTheme.allCases, id: \.self) { theme in
                            VStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(theme.backgroundColor)
                                    .frame(width: 60, height: 60)
                                    .overlay {
                                        if vm.theme == theme {
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(theme.accentColor, lineWidth: 4)
                                        }
                                    }
                                Text(theme.displayName)
                                    .font(bodyFont)
                            }
                            .onTapGesture { vm.theme = theme }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle(isOn: $vm.rulerEnabled) {
                        Text(L10n.readingRuler)
                            .font(labelFont)
                    }
                } footer: {
                    Text(L10n.rulerDescription)
                        .font(bodyFont)
                }

                Section {
                    Picker(L10n.languageLabel, selection: $vm.selectedLanguage) {
                        ForEach(vm.availableLanguages, id: \.code) { lang in
                            Text(lang.name)
                                .font(bodyFont)
                                .tag(lang.code)
                        }
                    }
                    .font(labelFont)
                }

                Section {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack {
                            Image(systemName: "crown.fill").foregroundColor(.orange)
                                .font(.title2)
                            Text(L10n.upgradePro)
                                .font(labelFont)
                        }
                    }
                }

                Section {
                    Button(L10n.resetSettings, role: .destructive) {
                        showResetAlert = true
                    }
                    .font(labelFont)
                }

                Section {
                    Text(L10n.versionFooter)
                        .font(bodyFont)
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
        .onChange(of: vm.fontSize) { _ in vm.save(to: settings) }
        .onChange(of: vm.theme) { _ in vm.save(to: settings) }
        .onChange(of: vm.lineHeight) { _ in vm.save(to: settings) }
        .onChange(of: vm.letterSpacing) { _ in vm.save(to: settings) }
        .onChange(of: vm.rulerEnabled) { _ in vm.save(to: settings) }
        .onChange(of: vm.selectedLanguage) { _ in vm.save(to: settings) }
    }
}
