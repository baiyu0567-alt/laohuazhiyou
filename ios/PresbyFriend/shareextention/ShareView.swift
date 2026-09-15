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
                ReaderView(text: text, paragraphs: paragraphs, onClose: { dismiss() })
                    .environmentObject(settings)
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
        let service = TextRecognitionService(
            languages: RecognitionLanguage.visionLanguages(
                systemLanguageCode: Locale.current.language.languageCode?.identifier,
                preference: settings.recognitionLanguage))

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

        let joined = blocks.map(\.text).joined(separator: "\n")
        if failed {
            error = L10n.ocrFail
        } else if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = L10n.ocrNoText
        } else {
            text = joined
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
