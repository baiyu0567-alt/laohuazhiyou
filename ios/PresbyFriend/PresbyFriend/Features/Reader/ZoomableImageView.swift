import SwiftUI
import UIKit

/// OCR 没认出文字时的兜底：显示原图，支持捏合缩放和拖动。
///
/// 用 `UIScrollView` 而不是 SwiftUI 的 `MagnificationGesture`——前者直接给出
/// 平滑的捏合 + 平移 + 回弹，不用自己维护缩放锚点和边界。
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    /// 最小缩放。默认 1 表示「适应屏幕」，用户可以往外捏。
    var minimumZoomScale: CGFloat = 1.0
    var maximumZoomScale: CGFloat = 8.0

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = minimumZoomScale
        scrollView.maximumZoomScale = maximumZoomScale
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .black

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        // 双击放大到 2 倍 / 还原。比拇指捏合更容易被老花眼用户发现。
        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
        context.coordinator.layout(in: scrollView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?

        func layout(in scrollView: UIScrollView) {
            guard let imageView else { return }
            scrollView.frame = scrollView.bounds
            imageView.frame = scrollView.bounds
            scrollView.contentSize = scrollView.bounds.size
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let imageView else { return }
            let offsetX = max((scrollView.bounds.width - imageView.frame.width) / 2, 0)
            let offsetY = max((scrollView.bounds.height - imageView.frame.height) / 2, 0)
            scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX,
                                                   bottom: offsetY, right: offsetX)
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = recognizer.location(in: imageView)
                let target = min(scrollView.maximumZoomScale, scrollView.minimumZoomScale * 2.5)
                let width = scrollView.bounds.width / target
                let height = scrollView.bounds.height / target
                scrollView.zoom(
                    to: CGRect(x: point.x - width / 2, y: point.y - height / 2,
                               width: width, height: height),
                    animated: true)
            }
        }
    }
}
