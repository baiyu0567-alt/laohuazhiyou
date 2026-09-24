import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsModel
    @EnvironmentObject var subscription: SubscriptionManager
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
                        // 这个数字**真的按 `vm.fontSize` 渲染**，是刻意的预览——让用户当场
                        // 看到调大之后有多大。
                        //
                        // 但预览不能反过来改这一行的布局：`Slider` 钉死 120pt、两个按钮各 36pt，
                        // 留给这段文字的只有约 119pt；而「72px」按 72pt 排开要 ~160pt。宽度不够
                        // 它会折成两行（预置 64 启动的截图里，「64」和「px」已经分了两行），
                        // 整行随之变高，滑块就在用户手指底下移位。
                        //
                        // 所以钉死宽度 + 限单行 + 放不下就缩字号：预览保留，行高与滑块位置恒定。
                        Text("\(Int(vm.fontSize))px")
                            .font(.system(size: CGFloat(vm.fontSize)))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .frame(width: 104, alignment: .leading)
                        Spacer()
                        // `.buttonStyle(.borderless)` 是**必须的**，不是修饰。
                        //
                        // `Form` 是 `List` 的皮。行内 `Button` 用默认的 `.automatic` 样式时，
                        // 样式会「适配容器」——点击目标被放大到**整行**。一行里只有一个按钮时
                        // 这样没问题（整行点哪儿都算它）；这一行有两个，两个都被放大到同一整行，
                        // 手势就分不出该给谁，两个按钮**都不响应**。
                        // 而 `Slider` 不是 `Button`，不走这条样式解析，自己的拖动照旧——这正是
                        // 「滑块能拖、两头的按钮按不动」的成因。
                        //
                        // 修法是给**两个**按钮都打上显式样式：只打一个没用，没打的那个
                        // 仍旧用 `.automatic`、仍旧铺满整行，会把打在另一个上的手势一起吃掉。
                        Button { vm.fontSize = max(24, vm.fontSize - 4) } label: {
                            Image(systemName: "minus.circle.fill").font(.system(size: 36))
                        }
                        .buttonStyle(.borderless)
                        Slider(value: $vm.fontSize, in: 24...72, step: 4)
                            .frame(width: 120)
                        Button { vm.fontSize = min(72, vm.fontSize + 4) } label: {
                            Image(systemName: "plus.circle.fill").font(.system(size: 36))
                        }
                        .buttonStyle(.borderless)
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
                    // ❗ 只在「实际用的识别语言 ≠ 系统语言那一档」时出现。常驻的话它在一个
                    // 一切正常的设置页上就只是个装饰；只在真的不一致时亮，它才带信息。
                    Picker(isLanguageMismatch ? "❗️ " + L10n.ocrLanguage : L10n.ocrLanguage,
                           selection: $vm.recognitionLanguage) {
                        Text(L10n.ocrLanguageFollowSystem)
                            .font(bodyFont)
                            .tag(RecognitionLanguage.followSystem)
                        // 手动档来自 Vision 的运行时清单（本机 33 种），不是写死的一份，
                        // 见 `OCRSupportedLanguageCodes`。名字用本族名，见
                        // `RecognitionLanguage.displayName(for:)`。
                        ForEach(supportedLanguageCodes, id: \.self) { code in
                            Text(RecognitionLanguage.displayName(for: code))
                                .font(bodyFont)
                                .tag(RecognitionLanguage.manual(code))
                        }
                    }
                    .font(labelFont)

                    // 选了「跟随系统」之后，界面上看不出实际用的是哪个模型——这一行写出来。
                    // 没有它的话，第一项和它的含义之间是断的，用户没法确认它究竟解析成了什么。
                    HStack {
                        Text(L10n.ocrLanguageCurrent)
                            .font(bodyFont)
                        Spacer()
                        Text(RecognitionLanguage.displayName(for: effectiveLanguageCode))
                            .font(bodyFont)
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.ocrLanguageDesc)
                        if isLanguageMismatch {
                            Text(L10n.ocrLanguageWarning)
                        }
                    }
                    .font(bodyFont)
                }

                // 已经是 Pro 就不再摆这个入口——对齐 Android `SettingsScreen.kt:179`
                // 的 `if (!isPro)`。留着它，付过费的用户点进去只会看到一张劝他付费的
                // 付费墙，那是**当面说错话**：钱已经付了。
                if !subscription.isProSubscriber {
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
                Button(L10n.close, role: .cancel) {}
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
        .onChange(of: vm.recognitionLanguage) { _ in vm.save(to: settings) }
    }

    // MARK: - 识别语言

    /// 手动档的选项来源：Vision 的运行时清单，按本族名排序，**外加当前这一档**（若它不在
    /// 清单里）。
    ///
    /// 为什么要补那一手：`Picker` 的 `selection` 只要没有相等的 tag 就渲染成空行——
    /// 值还在，界面上却是一个空白格，用户既看不出选的是什么，也看不出它其实用不了。
    /// 而 `recognitionLanguage` 确实可以不在清单里：迁移旧档位名时（`chinese` → `zh-Hans`）
    /// 按设计**不查** `supported`，而清单本身在查询失败时会退化成 `["en-US"]`
    /// ——更别说本版起 `stored(from:)` 对**任何**像语言码的存储值都原样保留（见那里）。
    ///
    /// 补进去而不是把值改掉：改成别的等于把用户选过的语言**静默重置**，正是迁移那段要避免
    /// 的事。补进去则界面照实显示他的选择，而下面「当前使用」那一行会写明真正在跑的是哪一档
    /// ——两行合起来是实话。
    private var supportedLanguageCodes: [String] {
        let catalog = OCRSupportedLanguageCodes.sorted
        guard case .manual(let code) = vm.recognitionLanguage,
              !catalog.contains(code) else { return catalog }
        return ([code] + catalog).sorted {
            RecognitionLanguage.displayName(for: $0) < RecognitionLanguage.displayName(for: $1)
        }
    }

    /// 这一档实际会用哪个模型。「跟随系统」由设备语言解析而来，手动档就是它自己。
    private var effectiveLanguageCode: String {
        RecognitionLanguage.effectiveLanguageCode(
            deviceLanguageCode: Locale.preferredLanguages.first,
            preference: vm.recognitionLanguage,
            supported: OCRSupportedLanguageCodes.all)
    }

    /// 实际用的与系统语言那一档是不是同一个。❗ 和提示文案都由它决定。
    ///
    /// 两边的码来自同一个 `supported` 和同一个设备语言码，比较才有意义；
    /// 各算各的（比如拿 `vm.recognitionLanguage` 直接和 `Locale` 比）会得到
    /// 「永远不一致」或「永远一致」这种恒定的假结果。
    private var isLanguageMismatch: Bool {
        effectiveLanguageCode != RecognitionLanguage.systemLanguageCode(
            deviceLanguageCode: Locale.preferredLanguages.first,
            supported: OCRSupportedLanguageCodes.all)
    }
}
