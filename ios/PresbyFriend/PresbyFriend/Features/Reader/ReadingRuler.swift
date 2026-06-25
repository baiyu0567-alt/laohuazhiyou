import SwiftUI

struct ReadingRuler: View {
    @Binding var yPosition: CGFloat

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 0)
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(height: 60)
                    .offset(y: yPosition)
            }
            .allowsHitTesting(false)
    }
}
