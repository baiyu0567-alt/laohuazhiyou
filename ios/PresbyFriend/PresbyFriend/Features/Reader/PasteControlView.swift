import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// `UIPasteControl` 的 SwiftUI 包装。
///
/// 为什么不用普通 Button + `UIPasteboard.general.string`：那样**每次点击**都会弹
/// 系统对话框，且无法用 API 查询用户的选择。`UIPasteControl` 是 Apple 认可的
/// 「用户意图」信号，永不弹窗。
///
/// 代价是标签字号不可调（`UIPasteControl.Configuration` 没有字号属性），
/// 所以调用方应把大字说明放在控件之外。
struct PasteControlView: UIViewRepresentable {
    /// 拿到粘贴的纯文本后回调（主线程）。
    let onPaste: (String) -> Void

    func makeUIView(context: Context) -> UIPasteControl {
        let config = UIPasteControl.Configuration()
        config.displayMode = .iconAndLabel
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .systemBlue
        config.baseForegroundColor = .white

        let control = UIPasteControl(configuration: config)
        control.target = context.coordinator
        return control
    }

    func updateUIView(_ uiView: UIPasteControl, context: Context) {
        context.coordinator.onPaste = onPaste
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPaste: onPaste) }

    /// `UIPasteControl` 的 target 需要是 `UIResponder` 并声明可接受的类型。
    final class Coordinator: UIResponder {
        var onPaste: (String) -> Void

        init(onPaste: @escaping (String) -> Void) {
            self.onPaste = onPaste
            super.init()
            pasteConfiguration = UIPasteConfiguration(
                acceptableTypeIdentifiers: [UTType.plainText.identifier])
        }

        override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
            itemProviders.contains { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }
        }

        override func paste(itemProviders: [NSItemProvider]) {
            for provider in itemProviders
            where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                    let text = (item as? String)
                        ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
                    guard let text, !text.isEmpty else { return }
                    DispatchQueue.main.async { self.onPaste(text) }
                }
                return
            }
        }
    }
}
