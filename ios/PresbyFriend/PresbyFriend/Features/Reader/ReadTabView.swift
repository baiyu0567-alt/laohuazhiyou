import SwiftUI

/// 「读取」tab：老花眼用户最高频的动作，值得一整屏、值得把按钮做大。
struct ReadTabView: View {
    @EnvironmentObject private var coordinator: ReaderLaunchCoordinator

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                pasteCard
            }
            .padding(20)
        }
        .navigationTitle(L10n.readTab)
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
}
