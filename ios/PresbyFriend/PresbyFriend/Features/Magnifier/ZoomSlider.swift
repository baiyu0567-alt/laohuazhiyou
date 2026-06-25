import SwiftUI

struct ZoomSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .frame(height: 6)

                Capsule()
                    .fill(.white)
                    .frame(width: max(0, min(geo.size.width, geo.size.width * (value - range.lowerBound) / (range.upperBound - range.lowerBound))), height: 6)

                Circle()
                    .fill(.white)
                    .frame(width: 28, height: 28)
                    .shadow(radius: 4)
                    .offset(x: max(0, min(geo.size.width - 28, (geo.size.width - 28) * (value - range.lowerBound) / (range.upperBound - range.lowerBound))))
                    .gesture(
                        DragGesture()
                            .onChanged { g in
                                let ratio = max(0, min(1, g.location.x / geo.size.width))
                                value = range.lowerBound + ratio * (range.upperBound - range.lowerBound)
                            }
                    )
            }
            .frame(height: 28)
        }
        .frame(height: 28)
    }
}
