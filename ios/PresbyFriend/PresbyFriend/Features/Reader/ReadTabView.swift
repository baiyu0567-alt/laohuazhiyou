import SwiftUI
import PhotosUI
import OSLog

/// 「读取」tab：老花眼用户最高频的动作，值得一整屏、值得把按钮做大。
struct ReadTabView: View {
    @EnvironmentObject private var coordinator: ReaderLaunchCoordinator
    @State private var photoItem: PhotosPickerItem?
    @State private var photoError: String?

    /// 本文件同时编译进 App 和分享扩展两个 target，所以 subsystem 跟着 `Bundle.main` 走，
    /// 不在扩展里冒充 App 的标识。
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.presbyfriend",
        category: "photo-ocr")

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                pasteCard
                photoCard
            }
            .padding(20)
        }
        .navigationTitle(L10n.readTab)
        .onChange(of: photoItem) { item in
            guard let item else { return }
            // 绑定必须在这里就清空，不能等 `load` 跑完——`load` 要等 OCR，
            // 首次可达 28–34s，而 `open(image:)` 在取消时并不会提前返回
            // （它的 `token == generation` 闸在 `recognize` 返回之后才执行）。
            // 有这段窗口，就有点「取消 → 再选同一张」的路径：SwiftUI 把同一个
            // 值写回绑定，`onChange` 的等值比较看不出变化，于是整个动作被静默
            // 吞掉——用户点了一下，没有加载、没有转圈、没有报错、没有跳转。
            // `load` 已按值持有 item，下面没有任何地方再读这个绑定。
            photoItem = nil
            Task { await load(item) }
        }
    }

    private var pasteCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.pasteAndMagnify)
                .font(.system(size: 34, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            PasteControlView { text in
                coordinator.open(text: text)
            }
            .frame(maxWidth: .infinity, minHeight: 88)

            Text(L10n.pasteHint)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(20)
    }

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.pickFromPhotos)
                .font(.system(size: 34, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(L10n.pickFromPhotos, systemImage: "photo.on.rectangle")
                    .font(.system(size: 26, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 88)
            }
            .buttonStyle(.borderedProminent)

            Text(photoError ?? L10n.pickPhotoHint)
                .font(.system(size: 18))
                .foregroundColor(photoError == nil ? .primary : .red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(20)
    }

    /// 加载/解码失败的唯一出口。
    ///
    /// 用户看到的文案只有一条（`L10n.photoLoadFail`），但三种成因——加载抛错、
    /// 返回空数据、拿到的字节解不出图——在日志里必须分得开，否则没人查得动。
    /// 原来用 `try?` 把它们一起抹平，等于把排查线索丢掉了。
    private func failLoad(_ reason: String) {
        Self.logger.error("\(reason, privacy: .public)")
        photoError = L10n.photoLoadFail
    }

    private func load(_ item: PhotosPickerItem) async {
        photoError = nil

        let data: Data?
        do {
            data = try await item.loadTransferable(type: Data.self)
        } catch {
            // 用 `String(describing:)` 而不是 `localizedDescription`：日志要留下错误
            // 的类型和 domain/code，那才是排查时要看的东西。
            failLoad("Photo picker loadTransferable threw: \(String(describing: error))")
            return
        }

        guard let data else {
            failLoad("Photo picker returned no data for the selected item")
            return
        }

        guard let source = OCRImageSource.from(data: data) else {
            failLoad("Selected photo (\(data.count) bytes) could not be decoded into a CGImage")
            return
        }

        await coordinator.open(image: source)
    }
}
