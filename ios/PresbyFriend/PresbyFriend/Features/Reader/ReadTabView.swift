import SwiftUI
import PhotosUI
import UIKit

/// 「读取」tab：老花眼用户最高频的动作，值得一整屏、值得把按钮做大。
struct ReadTabView: View {
    @EnvironmentObject private var coordinator: ReaderLaunchCoordinator
    @State private var photoItem: PhotosPickerItem?
    @State private var photoError: String?

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
                .foregroundColor(.secondary)
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
                .foregroundColor(photoError == nil ? .secondary : .red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(20)
    }

    private func load(_ item: PhotosPickerItem) async {
        photoError = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let source = OCRImageSource.from(data: data) else {
            photoError = L10n.photoLoadFail
            photoItem = nil
            return
        }
        await coordinator.open(image: source)
        photoItem = nil
    }
}
