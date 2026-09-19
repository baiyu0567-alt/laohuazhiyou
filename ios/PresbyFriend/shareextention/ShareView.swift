import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ShareView: View {
    let extensionContext: NSExtensionContext
    @State private var text: String?
    @State private var paragraphs: [String]?
    @State private var isLoading: Bool = false
    @State private var error: String?
    @StateObject private var settings = SettingsModel()

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text(L10n.ocrPreparing)
                        .font(.title3)
                }
            } else if let text {
                // ReaderView 不自带导航容器：它的 .navigationTitle/.toolbar 只是
                // 往祖先容器上挂，没有容器这三个工具项（关闭、字号面板、朗读）
                // 就一个都渲染不出来。分享扩展这条路径上没有任何系统导航栏
                // （ShareViewController 只做 UIViewController 容器），所以要在这里
                // 自己提供——与 App 内 PresbyFriendApp.swift:120-125 的包法一致。
                NavigationStack {
                    ReaderView(text: text, paragraphs: paragraphs, onClose: { dismiss() })
                        .environmentObject(settings)
                }
            } else if let error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text(error)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                    Button(L10n.close) { dismiss() }
                        .font(.title3)
                }
                .padding()
            } else {
                ProgressView()
                    .task { await loadSharedContent() }
            }
        }
        .onAppear {
            // 之前这里漏了：不 load() 就会一直用默认字号/主题，
            // 与 App 内设置不一致。
            settings.load()
        }
    }

    private func loadSharedContent() async {
        // 设置必须在读 `recognitionLanguage` 之前装好，所以在这里同步加载，而不是
        // 指望 `.onAppear` 先于 `.task` 跑完——SwiftUI 不保证这个顺序，而这里
        // 赌错的代价是识别模型选错：不报错、不崩溃，只是安静地输出垃圾
        // （实测中文图 + ["en-US"] 把「用法用量」认成 "mzms"）。
        // 上面的 `.onAppear` 保留，但真正决定性的调用是这一行。
        settings.load()

        isLoading = true
        defer { isLoading = false }

        guard let items = extensionContext.inputItems as? [NSExtensionItem] else { return }

        for item in items {
            guard let attachments = item.attachments else { continue }

            // Priority: text > URL > image (image OCR via VNRecognizeTextRequest later)
            if let text = await extractText(from: attachments) {
                self.text = text
                return
            }

            if let url = await extractURL(from: attachments) {
                await loadURL(url)
                return
            }

            if let source = await extractImage(from: attachments) {
                await loadImage(source)
                return
            }
        }

        error = L10n.urlExtractFail
    }

    private func extractText(from attachments: [NSItemProvider]) async -> String? {
        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
                return try? await provider.loadItem(forTypeIdentifier: "public.plain-text") as? String
            }
        }
        return nil
    }

    private func extractURL(from attachments: [NSItemProvider]) async -> URL? {
        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier("public.url") {
                let data = try? await provider.loadItem(forTypeIdentifier: "public.url")
                if let url = data as? URL { return url }
                if let urlString = data as? String, let url = URL(string: urlString) { return url }
            }
        }
        return nil
    }

    /// 从附件里取第一张可用的图。
    /// 三种形态都要兜：Data、临时文件 URL、以及同进程传过来的 UIImage。
    private func extractImage(from attachments: [NSItemProvider]) async -> OCRImageSource? {
        for provider in attachments
        where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let data = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) as? Data,
               let source = OCRImageSource.from(data: data) {
                return source
            }
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) as? URL,
               let data = try? Data(contentsOf: url),
               let source = OCRImageSource.from(data: data) {
                return source
            }
            if let image = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) as? UIImage,
               let source = OCRImageSource.from(uiImage: image) {
                return source
            }
        }
        return nil
    }

    private func loadImage(_ source: OCRImageSource) async {
        // 与 App 内 `ContentView.applyRecognitionLanguages()` 同一套输入：**设备语言** +
        // 用户选的档位。两边共享同一个 `SettingsModel`（`ios-v1` 上经 App Group），
        // 所以同一台设备上 App 和扩展解析出同一档。
        //
        // ⚠️ 本分支 `device-test-noshare` 关掉了 App Group（免费 Personal Team 签不了），
        // 扩展读到的 `settings.recognitionLanguage` 是它自己容器里的默认值 `.followSystem`，
        // 而设备语言两边是同一个，所以**默认档在扩展里依然是对的**——这一点比改动前好：
        // 以前这里读的是 `settings.language`（界面语言），扩展拿到的一律是 `"en"`，
        // 于是「跟随 App 语言」在扩展里恒为 `en-US`。现在默认档不再依赖那个读不到的值了。
        // 仍然读不到的是**用户手动选的档位**，那要等合并回 `ios-v1`（App Group 恢复）。
        let deviceLanguageCode = Locale.preferredLanguages.first
        let service = TextRecognitionService(
            languages: RecognitionLanguage.visionLanguages(
                deviceLanguageCode: deviceLanguageCode,
                preference: settings.recognitionLanguage,
                supported: OCRSupportedLanguageCodes.all))

        // ⚠️ **分享扩展这条路径有意不设免费额度闸**，这是已知行为，不是漏掉的 bug。
        //
        // 三条理由，缺一条都不成立：
        //  1. 扩展里**卖不了东西**。`Product.purchase()` 需要 UI 场景锚点，在 app
        //     extension 里会以 "Could not find a UI anchor for … purchase." 失败。
        //     所以在这里拦下用户是条死路：既不能买也不能恢复，只能把人赶走。
        //  2. Android 侧同样没闸。那边 `canUseToday()` 只出现在
        //     `PresbyFriendAccessibilityService` 一处；`ACTION_SEND` / `ACTION_PROCESS_TEXT`
        //     直达阅读页，不计数。扩展就是 iOS 的 `ACTION_SEND` 面，对齐即不设闸。
        //  3. 本分支（`device-test-noshare`）App Group 是关掉的，扩展读不到 App 的
        //     `UserDefaults`，额度与 Pro 状态一条都拿不到。硬要设闸只能改成「扩展只计数
        //     不提示」——那是让用户**静默丢额度**，比不计数更坏。
        //
        // 后果写清楚：用户可以把图片分享给扩展、无限制地阅读，绕过每日 10 次。
        // 将来要堵，需要同时满足「App Group 恢复」+「扩展里放一个只读的『已到今日上限，
        // 请打开 App』面板」，属于独立需求。
        //
        // 这里不能再用 `try?`：它把 Vision 的抛错折成 `[]`，和「这张图真的没有文字」
        // 撞成同一个值，于是识别失败会被当成空结果报给用户。两种结果必须留下
        // 不同的痕迹——和 ReaderLaunchCoordinator 里 Task 7 的修法一致。
        let blocks: [RecognizedBlock]
        var failed = false
        do {
            blocks = try await service.recognize(source)
        } catch {
            blocks = []
            failed = true
        }

        // 与 App 内 `ReaderLaunchCoordinator.open(image:)` 同一套：视觉行 → 段落，
        // 段落之间用 `"\n\n"` 接。分享扩展这条路径此前只 `"\n"` 接视觉行，
        // 于是 `ReaderView` 整篇渲染成一个 `Text`——和 App 内那个已修的毛病同一个。
        let recognized = TextLayout.paragraphs(from: blocks.map(\.line))
        let joined = recognized.joined(separator: "\n\n")
        if failed {
            error = L10n.ocrFail
        } else if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // 不能复用 `ocrNoText`：那句是「No text found in this picture. Showing the
            // original — pinch to zoom.」，而本分支渲染的是 error 面板（上面一个警告三角
            // + 文案 + Close），**根本没有原图**——它在对用户下一条做不到的指令。
            // `ocrNoText` 的捏合提示在 App 内（PresbyFriendApp.swift 的兜底原图分支，
            // 那里真有 ZoomableImageView）是**对的**，所以不能改它的值。
            // 改用这个目前无人引用的通用键（六语言现成，值为「No text found on this
            // screen」及其五语对应；「screen」用在图片场景下不够贴切，但不是假话）。
            error = L10n.noTextFound
        } else {
            text = joined
            paragraphs = recognized
        }
    }

    private func loadURL(_ url: URL) async {
        do {
            let extractor = URLExtractor()
            let content = try await extractor.extract(from: url.absoluteString)
            if content.count > 50 {
                text = content
            } else {
                error = L10n.urlExtractFail
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func dismiss() {
        extensionContext.completeRequest(returningItems: nil)
    }
}
