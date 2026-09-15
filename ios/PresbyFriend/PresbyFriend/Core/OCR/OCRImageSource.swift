import Foundation
import UIKit
import ImageIO
import CoreGraphics

/// 一张待识别的图，连同它的方向。
///
/// 三个来源（相册选图 / 分享附件 / 相机快门）都归一到这个类型，
/// 这样 `TextRecognitionService` 不需要知道图是从哪来的。
///
/// **为什么要带方向：** `CGImageSourceCreateImageAtIndex` 不会应用 EXIF 方向。
/// 手机摄像头传感器是横向的，照片通常带方向元数据。忽略它会让 Vision 拿到一张
/// 躺倒的图，识别质量下降甚至返回空——不报错，只是结果不对。
struct OCRImageSource {
    var image: CGImage
    var orientation: CGImagePropertyOrientation = .up

    /// 从图片二进制（相册选图、分享附件、`AVCapturePhoto.fileDataRepresentation()`）构造。
    static func from(data: Data) -> OCRImageSource? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let raw = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        return OCRImageSource(image: img,
                              orientation: CGImagePropertyOrientation(rawValue: raw) ?? .up)
    }

    /// 从 `UIImage` 构造（部分分享扩展的 `NSItemProvider` 直接给 `UIImage`）。
    static func from(uiImage: UIImage) -> OCRImageSource? {
        guard let cg = uiImage.cgImage else { return nil }
        let orientation: CGImagePropertyOrientation
        switch uiImage.imageOrientation {
        case .up:            orientation = .up
        case .down:          orientation = .down
        case .left:          orientation = .left
        case .right:         orientation = .right
        case .upMirrored:    orientation = .upMirrored
        case .downMirrored:  orientation = .downMirrored
        case .leftMirrored:  orientation = .leftMirrored
        case .rightMirrored: orientation = .rightMirrored
        @unknown default:    orientation = .up
        }
        return OCRImageSource(image: cg, orientation: orientation)
    }

    /// 转成可以直接显示的 `UIImage`。
    ///
    /// **必须带上方向。** `CGImageSourceCreateImageAtIndex` 不会应用 EXIF 方向，
    /// 而 `UIImage(cgImage:)` 默认按 `.up` 解释——竖拍照片会整张躺倒。
    /// OCR 路径是把方向交给 `VNImageRequestHandler` 处理的；显示路径只有这里能补上，
    /// 所以这是全项目唯一的方向转换点，调用方不该再自己拼 `UIImage`。
    ///
    /// 下面的 switch 是上面 `from(uiImage:)` 的逆映射。两个枚举的 case 名字一一对应
    /// （raw value 不同，语义相同），所以形状完全一致——不要另立一套约定。
    var uiImage: UIImage {
        let orientation: UIImage.Orientation
        switch self.orientation {
        case .up:            orientation = .up
        case .down:          orientation = .down
        case .left:          orientation = .left
        case .right:         orientation = .right
        case .upMirrored:    orientation = .upMirrored
        case .downMirrored:  orientation = .downMirrored
        case .leftMirrored:  orientation = .leftMirrored
        case .rightMirrored: orientation = .rightMirrored
        @unknown default:    orientation = .up
        }
        return UIImage(cgImage: image, scale: 1, orientation: orientation)
    }
}
