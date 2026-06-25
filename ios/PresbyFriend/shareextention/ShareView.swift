import SwiftUI

struct ShareView: View {
    let extensionContext: NSExtensionContext
    @State private var text: String?
    @State private var paragraphs: [String]?
    @State private var isLoading: Bool = false
    @State private var error: String?
    @StateObject private var settings = SettingsModel()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text(L10n.loadingUrl)
                    }
                } else if let text {
                    ReaderView(text: text, paragraphs: paragraphs)
                        .environmentObject(settings)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(L10n.close) { dismiss() }
                            }
                        }
                } else if let error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                        Text(error)
                        Button(L10n.close) { dismiss() }
                    }
                    .padding()
                } else {
                    ProgressView()
                        .task { await loadSharedContent() }
                }
            }
        }
    }

    private func loadSharedContent() async {
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
