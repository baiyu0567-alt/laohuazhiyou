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
        let coordinator = context.coordinator
        guard let imageView = coordinator.imageView else { return }

        // 同一性比较：`UIImage` 是引用类型，`!=` 会走 `isEqual` 逐像素比较，
        // 每次重绘都全图比一遍。
        if imageView.image !== image {
            // 换图：旧图的缩放和位移对新图没有意义，回到基础缩放再重新布局。
            imageView.image = image
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
            coordinator.layout(in: scrollView)
            return
        }

        // 图没变。**只有确认没有 transform 时才能重新布局。**
        // SwiftUI 重绘不是用户操作，不得把用户的缩放/位移抹掉。
        if coordinator.isAtBaseScale(in: scrollView) {
            coordinator.layout(in: scrollView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?

        /// 现在能不能安全地重设尺寸。
        ///
        /// `UIScrollView` 的缩放是靠给被缩放的子视图加 **transform** 实现的。
        /// UIKit 明确规定：`transform` 非 identity 时 `frame` 未定义、不得修改。
        /// 一旦违反，图被打回视口大小而 `zoomScale` 仍报告放大后的值——
        /// 视觉上没放大、逻辑上放大了，下一次双击就会走错分支（还原而不是放大）。
        /// 所以判据是 transform 是否 identity，缩放倍率只作辅助（回弹时倍率会
        /// 短暂低于最小值，但 transform 已经存在）。
        func isAtBaseScale(in scrollView: UIScrollView) -> Bool {
            guard let imageView else { return false }
            return imageView.transform.isIdentity
                && scrollView.zoomScale <= scrollView.minimumZoomScale + 0.0001
        }

        func layout(in scrollView: UIScrollView) {
            guard let imageView else { return }
            scrollView.frame = scrollView.bounds
            // 用 bounds + center 而不是 frame：即便万一在 transform 存在时被调到，
            // 这两个属性仍是良定义的。
            imageView.bounds = CGRect(origin: .zero, size: scrollView.bounds.size)
            imageView.center = CGPoint(x: scrollView.bounds.midX,
                                       y: scrollView.bounds.midY)
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
