import SwiftUI

struct ReaderView: View {
    @EnvironmentObject var settings: SettingsModel
    @StateObject private var vm = ReaderViewModel()
    @State private var rulerY: CGFloat = 0

    let incomingText: String
    let incomingParagraphs: [String]?
    let onClose: (() -> Void)?

    init(text: String, paragraphs: [String]? = nil, onClose: (() -> Void)? = nil) {
        incomingText = text
        incomingParagraphs = paragraphs
        self.onClose = onClose
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            vm.theme.backgroundColor.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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
                .overlay {
                    if vm.rulerEnabled {
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { rulerY = geo.frame(in: .global).minY }
                                .onChange(of: geo.frame(in: .global).minY) { _, new in
                                    rulerY = new
                                }
                        }
                    }
                }
            }

            if vm.rulerEnabled {
                ReadingRuler(yPosition: $rulerY)
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
