import SwiftUI

struct ReaderView: View {
    @EnvironmentObject var settings: SettingsModel
    @StateObject private var vm = ReaderViewModel()
    @State private var rulerY: CGFloat = 0

    let incomingText: String
    let incomingParagraphs: [String]?
    /// 识别语言可能选错了的提示。判定在 `ReaderLaunchCoordinator.hint(for:failed:)`，
    /// 这里只负责显示。nil = 不显示。
    let languageHint: LanguageHint?
    let onClose: (() -> Void)?

    init(text: String,
         paragraphs: [String]? = nil,
         languageHint: LanguageHint? = nil,
         onClose: (() -> Void)? = nil) {
        incomingText = text
        incomingParagraphs = paragraphs
        self.languageHint = languageHint
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            vm.theme.backgroundColor.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let languageHint {
                        languageHintCard(languageHint)
                    }

                    if !vm.paragraphs.isEmpty {
                        ForEach(Array(vm.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                            Text(paragraph)
                                .font(.system(size: vm.fontSize))
                                .foregroundColor(vm.theme.textColor)
                                .lineSpacing(vm.fontSize * (vm.lineHeight - 1.0))
                                .kerning(vm.letterSpacing)
                                .padding(.horizontal, 24)

                            if index < vm.paragraphs.count - 1 {
                                Divider()
                                    .overlay(vm.theme.textColor.opacity(0.2))
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                            }
                        }
                    } else {
                        Text(vm.text)
                            .font(.system(size: vm.fontSize))
                            .foregroundColor(vm.theme.textColor)
                            .lineSpacing(vm.fontSize * (vm.lineHeight - 1.0))
                            .kerning(vm.letterSpacing)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 标尺的坐标基准是**阅读区顶边**（这个 `GeometryReader` 的 `0`），不是滚动
            // 内容，也不是屏幕底边。原先这里挂着一个量「滚动内容顶边的全局 Y」的
            // `GeometryReader`，把那个数喂给锚在底边的带子——落点因此在屏幕外。
            // 位置现在完全由用户拖出来，见 `ReadingRuler`。
            if vm.rulerEnabled {
                GeometryReader { geo in
                    ReadingRuler(yPosition: $rulerY,
                                 lineHeight: vm.fontSize * vm.lineHeight * 1.2,
                                 maxY: geo.size.height,
                                 accent: vm.theme.accentColor)
                }
            }

            if vm.controlsVisible {
                controlsPanel
                    .transition(.move(edge: .bottom))
            }
        }
        .navigationTitle(L10n.readingMode)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.close) { onClose() }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { vm.controlsVisible.toggle() }
                } label: {
                    Image(systemName: "textformat.size")
                        .font(.title2)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    vm.toggleSpeaking()
                } label: {
                    Image(systemName: vm.isSpeaking ? "stop.circle.fill" : "play.circle")
                        .font(.title2)
                }
            }
        }
        .onAppear {
            if let paragraphs = incomingParagraphs, !paragraphs.isEmpty {
                vm.paragraphs = paragraphs
                vm.text = paragraphs.joined(separator: "\n\n")
            } else {
                vm.setParagraphs(from: incomingText)
            }
            vm.loadSettings(from: settings)
        }
        .onDisappear {
            vm.stopSpeaking()
            vm.saveToSettings(settings)
        }
    }

    // MARK: - Language Hint

    /// 「识别语言可能选错了」。放在正文**最上面**：用户看到一段乱码时，第一个要能看到的
    /// 就是「这不一定是字写得不好，可能是语言选错了」。
    ///
    /// 字号跟着阅读字号缩放而不是写死：这个 App 的用户就是看不清小字才来的，
    /// 提示本身若是小字，等于把提示藏起来。但也不与正文同大，否则它看起来像正文的一部分。
    /// 底色用 `textColor` 的淡色而不是 `.ultraThinMaterial`：阅读页有四套主题，
    /// 材质在浅色/深色主题下观感不一致，而正文色是跟着主题走的。
    private func languageHintCard(_ hint: LanguageHint) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.ocrHintLanguageTitle)
                .font(.system(size: max(20, vm.fontSize * 0.6), weight: .semibold))
            // 两种理由说的是两件事，所以取两条不同的文案——都带两个语言名，
            // 但第二个名是「系统语言」还是「建议改用的语言」完全不同。
            // 分派在 `languageHintBody` 里，两张卡片共用那一份，不在这里重写。
            Text(languageHintBody(hint))
                .font(.system(size: max(18, vm.fontSize * 0.5)))
        }
        .foregroundColor(vm.theme.textColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(vm.theme.textColor.opacity(0.12))
        .cornerRadius(12)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    // MARK: - Controls Panel

    private var controlsPanel: some View {
        VStack(spacing: 16) {
            HStack {
                Text(L10n.fontSize)
                    .foregroundColor(vm.theme.textColor)
                Spacer()
                Button { vm.adjustFontSize(by: -1) } label: {
                    Image(systemName: "minus.circle.fill").font(.title2)
                }
                Text("\(Int(vm.fontSize))px")
                    .foregroundColor(vm.theme.accentColor)
                    .frame(minWidth: 48)
                Button { vm.adjustFontSize(by: 1) } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
            }

            HStack {
                Text(L10n.themeLabel)
                    .foregroundColor(vm.theme.textColor)
                Spacer()
                ForEach(ReadingTheme.allCases, id: \.self) { theme in
                    Circle()
                        .fill(theme.backgroundColor)
                        .frame(width: 32, height: 32)
                        .overlay(Circle().stroke(vm.theme == theme ? vm.theme.accentColor : .clear, lineWidth: 3))
                        .onTapGesture { vm.theme = theme }
                }
            }

            HStack {
                Text(L10n.lineHeight)
                    .foregroundColor(vm.theme.textColor)
                Spacer()
                Button { vm.adjustLineHeight(by: -0.2) } label: {
                    Image(systemName: "minus.circle.fill").font(.title2)
                }
                Text(String(format: "%.1f", vm.lineHeight))
                    .foregroundColor(vm.theme.accentColor)
                    .frame(minWidth: 36)
                Button { vm.adjustLineHeight(by: 0.2) } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
            }

            HStack {
                Text(L10n.letterSpacing)
                    .foregroundColor(vm.theme.textColor)
                Spacer()
                Button { vm.adjustLetterSpacing(by: -0.5) } label: {
                    Image(systemName: "minus.circle.fill").font(.title2)
                }
                Text(String(format: "%.1fpx", vm.letterSpacing))
                    .foregroundColor(vm.theme.accentColor)
                    .frame(minWidth: 48)
                Button { vm.adjustLetterSpacing(by: 0.5) } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding()
    }
}
