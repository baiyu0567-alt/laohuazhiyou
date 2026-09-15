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
}
