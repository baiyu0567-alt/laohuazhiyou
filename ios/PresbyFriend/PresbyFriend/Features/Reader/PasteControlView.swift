import SwiftUI
import UIKit
import UniformTypeIdentifiers
import OSLog

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
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, error in
                    if let error {
                        // 以前这里写的是 `_`，粘贴失败就彻底没有痕迹（和 `ReadTabView` 里
                        // 修掉的 `try?` 是同一类）。用户看到的仍然只是「点了没反应」，
                        // 但排查至少留得下线索。Logger 就地构造：这个回调不在主线程上，
                        // 所以不引入任何需要隔离的共享状态。
                        Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.presbyfriend",
                               category: "paste")
                            .error("Paste failed: \(String(describing: error))")
                        return
                    }
                    guard let text = Self.text(from: item), !text.isEmpty else {
                        // 走到这里说明**三条路都没接住**。原来这里是个**静默 `return`**
                        // ——和 `ReadTabView` 里修掉的 `try?` 是同一类：用户看到的只有
                        // 「点了没反应」，排查零线索。真机上确实走到过这里，见 `text(from:)`。
                        Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.presbyfriend",
                               category: "paste")
                            .error("Paste dropped: \(item.map { String(describing: type(of: $0)) } ?? "nil") could not be read as text")
                        return
                    }
                    DispatchQueue.main.async { self.onPaste(text) }
                }
                return
            }
        }

        /// 把 `loadItem` 交回来的对象翻成字符串。
        ///
        /// 真机实测（iPhone 11 Pro Max，从别的 App 复制纯文本）：剪贴板声明的是
        /// `public.utf8-plain-text`，`loadItem` 交代回来的却是一个 **`NSURL`**：
        /// ```
        /// file:///var/mobile/Library/Caches/com.apple.Pasteboard/<uuid>/<hash>
        /// ```
        /// ——**正文在那个文件里，不在 URL 里**。原实现只认 `String` 和 `Data`，
        /// 两种转换都失败，于是 `guard` 静默丢弃：用户那边粘贴横幅照弹（那是 iOS
        /// 弹的，说明粘贴本身成功），App 却毫无反应。
        ///
        /// 两个反直觉的点，都是真机上量出来的，别照着直觉得改：
        /// - **必须 `startAccessingSecurityScopedResource()`**。那个文件在粘贴板
        ///   守护进程的容器里（`/var/mobile/Library/Caches/com.apple.Pasteboard/`），
        ///   在我们沙箱之外，URL 带的隐式沙箱扩展不显式兑现就**读不到**——
        ///   裸 `Data(contentsOf:)` 会抛错。少了这一步的版本真机验证过，确实不通。
        /// - **别拿 `FileManager.fileExists` 当闸**。实测它对这个**能读**的文件返回
        ///   `false`（同一份数据紧接着 `Data(contentsOf:)` 读出了 946 字节）。
        ///   用它做前置检查，等于给自己造一条永远走不通的路。
        ///
        /// 另一条被真机证伪的路，记在这里免得有人再试：换成请求 provider
        /// **实际注册**的具体类型（`public.utf8-plain-text`）而不是父类型
        /// （`public.plain-text`），交回来的**是同一个文件 URL**。
        /// 交文件 URL 不是父类型强制转换的产物，是粘贴板本来的形态。
        ///
        /// `nonisolated` 不是可有可无的：`Coordinator` 继承自 `@MainActor` 的
        /// `UIResponder`，而 `loadItem` 的回调不在主 actor 上；不加这个修饰词，
        /// App target（`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`）会拒绝这次调用。
        /// 本文件同时编译进分享扩展，那边的默认隔离**不是** MainActor——两种设置
        /// 下都得站得住（见 `project.pbxproj:392/:427` 与 `:458/:487`）。
        nonisolated private static func text(from item: NSSecureCoding?) -> String? {
            if let string = item as? String { return string }
            if let data = item as? Data { return String(data: data, encoding: .utf8) }

            guard let url = item as? URL else { return nil }
            // 非文件 URL：粘贴的本身就是个网址，它的字符串形式就是正文。
            // 这条分支**没有**在真机上验过（没复制过网址），留着只是为了别让
            // 它掉进 `guard` 被静默丢弃。**绝不能**在这里调 `Data(contentsOf:)`
            // ——那会对着 http 地址发一次同步网络请求，把回调线程卡住。
            guard url.isFileURL else { return url.absoluteString }

            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            // 必须**在这次回调里**同步读掉：那是临时文件，回调返回后不再保证存在。
            // 丢给主线程稍后再读，会读到「文件不存在」——同一个 bug 换个地方复发。
            return (try? Data(contentsOf: url))
                .flatMap { String(data: $0, encoding: .utf8) }
        }
    }
}
