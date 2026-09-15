import AVFoundation
import SwiftUI
import Combine
import CoreGraphics

/// **为什么必须是 `NSObject` 子类**：`AVCapturePhotoCaptureDelegate` 继承
/// `NSObjectProtocol`，而 Swift 不允许纯 Swift 类声明这个 conformance
/// （`cannot declare conformance to 'NSObjectProtocol' in Swift; … should inherit
/// 'NSObject' instead`）。这是拍照回调的硬要求，不是风格偏好。
///
/// **隔离模式注意**：本文件被 **两个 target** 编译，而它们的编译参数不同——
/// app target 带 `-default-isolation=MainActor`（Xcode 26 的 approachable
/// concurrency，工程里 `SWIFT_APPROACHABLE_CONCURRENCY = YES`），shareextention
/// target 不带。于是同一个类在 app 里默认 `@MainActor`、在扩展里是 nonisolated。
/// 拍照这块要跨线程碰的状态因此**不能靠默认隔离来保护**，必须自带锁，
/// 见 `photoSlot` 与 `MagnifierViewModel.photoOutput(_:didFinishProcessingPhoto:error:)`。
final class MagnifierViewModel: NSObject, ObservableObject {
    @Published var zoomLevel: CGFloat = 2.0
    @Published var flashlightOn: Bool = false
    @Published var cameraAccessGranted: Bool = false
    @Published var cameraError: String?

    /// 是否有一张照片正在拍。UI 靠它把快门显示成「已经按下去了」的样子——
    /// 第二下点击不能看起来和「什么都没发生」一模一样。
    /// 只在主线程写（`capturePhoto()` 经 `MainActor.run`）。
    @Published private(set) var isCapturing = false

    /// 会话是否已经在跑。`startSession()` 把 `startRunning()` 丢到后台队列，返回之后到
    /// 真正跑起来之间有一小段空窗；那段时间里按快门会命中 `capturePhoto()` 的
    /// `session.isRunning` 闸直接返回 nil——按钮看起来能用，按下去什么都没发生。
    /// 用这个标志让快门在那段窗口里显示成不可用。
    ///
    /// **只在主线程写**：`startSession()` 的 `startRunning()` 在后台队列上返回，
    /// 若在那里直接赋值，就是一次从后台线程发布的 SwiftUI 变更。
    ///
    /// 两个 target 的默认隔离不同，而这段写法必须在**两边都成立**：app target 默认
    /// `@MainActor`，这个属性本身就是 main actor 隔离的，并发检查一收紧，那次后台写
    /// 就会被编译器指出来；shareextention target 默认 nonisolated，同一个类在那里没有
    /// 隔离可言，同一句写从隔离角度完全合法。所以正确性不押在默认隔离上——那条路径
    /// 显式回 `@MainActor` 再写。
    @Published private(set) var isSessionRunning = false

    /// 会话代次。每次 `startSession()` / `stopSession()` 自增。
    ///
    /// **为什么需要它**：`startSession()` 把 `startRunning()` 丢到全局队列上阻塞执行，收尾
    /// 却是一个独立的 `Task { @MainActor }`。那个收尾可能在 `stopSession()`（它把
    /// `isSessionRunning` 置回 false）**之后**才落地：`startRunning()` 还阻塞着时用户离开
    /// 放大镜页、回来又重新 `startSession()`，而**第一次**那个块的收尾仍可能晚到——于是
    /// `isSessionRunning == true` 而 `session.isRunning == false`，`MagnifierView` 的快门
    /// `.disabled(vm.isCapturing || !vm.isSessionRunning)` 把它显示成**可用**，按下却撞上
    /// `capturePhoto()` 的 `guard session.isRunning` 直接返回 nil：一个「看着能用、按了
    /// 没反应」的控件。收尾时对一次代次即可丢弃过期的那次写入。
    ///
    /// 与 `ReaderLaunchCoordinator.generation` 同一套路。**在 app target 里**读写都在主
    /// actor 上（`startSession()` / `stopSession()` 的调用点，以及下面那个 `@MainActor`
    /// 闭包）。本文件同时被扩展 target 编译，那边没有默认隔离（见文件头），所以这条隔离
    /// 论证只对 app target 成立——扩展里的正确性不靠它，靠的是扩展侧根本没有
    /// `MagnifierViewModel` 的调用点。沿用本文件既有的写法：不新引一层隔离，也不在闭包
    /// 里读 `session.isRunning`。
    private var sessionGeneration = 0

    let session = AVCaptureSession()

    /// 复用正在跑的 session 出图：比再起一套相机 UI 快，用户也不用第二次对准。
    let photoOutput = AVCapturePhotoOutput()

    private let device: AVCaptureDevice? = {
        if let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
            return device
        }
        if let device = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            return device
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }()

    /// 在途拍照的状态，放在一个独立的、自带锁的非隔离盒子里。
    ///
    /// **为什么要这个盒子**：三边都要读写它——`capturePhoto()`（在 app target 里是
    /// `@MainActor`、在扩展里是 nonisolated，与下面两方都不在同一个执行器上）、
    /// `photoOutput(_:didFinishProcessingPhoto:error:)`（AVFoundation 在自己的
    /// 队列上回调，头文件 AVCapturePhotoOutput.h 明确写 "not necessarily the main
    /// queue"）、以及 `withTaskCancellationHandler` 的取消处理器（任意线程）。
    /// 裸读写是数据竞争（与 Task 6 在识别服务的 `languages` 上修的是同一类缺陷），
    /// 而且这个文件在两个 target 里的默认隔离还不一样，靠隔离保护不了。
    ///
    /// **为什么是独立的 `NSLock` 而不是某把队列 + `queue.sync`**：与 Task 6 在
    /// `TextRecognitionService.languages` 上的裁决同一个道理——这里保护的只是两个
    /// 小值（在途标志 + 待 resume 的 continuation），一把独立的锁就够，而且锁内
    /// 绝不做任何阻塞调用（`finish` 是解锁之后才 resume 的）。
    ///
    /// **别拿「队列会被首次预热带住 28–34s」当这条选择的依据**：那条理由说的是
    /// `TextRecognitionService.queue`——它串行化的对象是整段 Vision 请求
    /// （`recognize`），首次 `prewarm` 要占住它 28–34s（见 `prewarm()` 的注释），
    /// 因此只排除「复用那把队列」这一种做法；本文件跟那个服务没有任何关系，这里
    /// 自建一把专用队列也不会被预热拖住。（本段以前是错的，已改正。）
    private let photoSlot = PhotoCaptureSlot()

    func requestAccess() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            cameraAccessGranted = true
            startSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run {
                cameraAccessGranted = granted
                if granted { startSession() }
                else { cameraError = L10n.cameraError }
            }
        default:
            await MainActor.run { cameraError = L10n.cameraPermissionRequired }
        }
    }

    private func startSession() {
        guard let device else { return }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            if session.canAddInput(input) { session.addInput(input) }
            // 在 commitConfiguration 之前挂上输出：配置提交后再改要另开一次配置块。
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            session.commitConfiguration()
            // 起这一次的后台块之前先占一个代次，收尾时对不上就丢弃（见 `sessionGeneration`）。
            sessionGeneration += 1
            let token = sessionGeneration
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                self.session.startRunning()
                // 回主线程再写 `@Published`：这段闭包跑在后台队列上（`startRunning()`
                // 会阻塞，不能占住主线程），在这里直接赋值就是从后台线程发布一次
                // SwiftUI 变更。两个 target 的默认隔离不同（见 `isSessionRunning` 的
                // 注释），所以不靠隔离，统一显式回 `@MainActor` 再写。
                Task { @MainActor in
                    guard self.sessionGeneration == token else { return }
                    self.isSessionRunning = true
                }
            }
            applyZoom()
        } catch {
            cameraError = L10n.cameraError
        }
    }

    func applyZoom() {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            let clamped = min(max(zoomLevel, 1.0), min(8.0, device.activeFormat.videoMaxZoomFactor))
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {}
    }

    func toggleFlashlight() {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            flashlightOn.toggle()
            device.torchMode = flashlightOn ? .on : .off
            device.unlockForConfiguration()
        } catch {}
    }

    func stopSession() {
        session.stopRunning()
        // 会话停了，拍照回调就不再保证会来。不在这里把在途的那一按收掉的话，
        // 它永远不完成，快门会一直停在忙碌态（`isCapturing` 为真）再也按不动。
        photoSlot.finish(with: nil)
        if let device, device.hasTorch, device.torchMode == .on {
            try? device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
        }
        flashlightOn = false
        // 与 `isSessionRunning = false` 同处自增：作废在途的那次 `startSession()` 收尾，
        // 否则它会在会话已停之后把 `isSessionRunning` 写回 true（见 `sessionGeneration`）。
        sessionGeneration += 1
        isSessionRunning = false
    }

    func detectedTextTapped(_ text: String) {
        // Handled by parent view — navigates to ReaderView
    }

    // MARK: - 拍照

    /// 拍一张并转成待识别的图。
    ///
    /// 失败返回 nil（不抛错——拍照失败对用户来说就是「没反应」，让调用方决定怎么提示）。
    /// 「已经有一张在途」同样返回 nil，但那一按不会静默消失：调用方靠 `isCapturing`
    /// 把快门显示成忙碌态（见 `MagnifierView`）。
    func capturePhoto() async -> OCRImageSource? {
        guard cameraAccessGranted, session.isRunning else { return nil }
        // 单飞闸：同一时刻只允许一次拍照在途。抢不到闸的这次直接退出——**绝不覆盖**
        // 在途那次的 continuation：覆盖等于把第一按的 Task 永远挂住（checked
        // continuation 还会额外报「泄漏」误用）。手抖双击正是这条闸要挡的。
        guard photoSlot.begin() else { return nil }
        // 闸的释放交给 defer：以后在这条 begin() 与 end() 之间插入任何提前返回
        // （新的 guard / try）都会静默把闸留在占住状态，也就是快门再也按不动。
        defer { photoSlot.end() }

        await MainActor.run { isCapturing = true }

        // 拍照回调只把 JPEG 字节交回来（`Data` 是 Sendable，谁也不跨隔离域）。
        let data = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                // 任务在进入本闭包之前就可能已是取消态（那时 `onCancel` 已经先跑过一遍、
                // 槽里是空的）。现在再把 continuation 放进去就没人来取了——Task 永远
                // 不完成，checked continuation 还会报泄漏。先看一眼。
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                    return
                }
                photoSlot.store(continuation)
                photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        } onCancel: {
            // 取消也必须把在途的 continuation 收掉。否则「按下快门 → 离开放大镜页」
            // （`MagnifierView.onDisappear` 取消这个 Task）而拍照回调不再来时，
            // 这个 Task 永远不完成。被取消的这一按按「没拍到」处理。
            photoSlot.finish(with: nil)
        }

        await MainActor.run { isCapturing = false }

        // 解析放在这里、不放拍照回调里：本方法在 app target 是 `@MainActor`、
        // 在扩展 target 是 nonisolated，恰好与 `OCRImageSource.from(data:)` 在两边
        // 各自的隔离一致；放进显式 `nonisolated` 的回调里就是跨隔离域调用。
        guard let data, let source = OCRImageSource.from(data: data) else { return nil }
        // 方向交给 OCRImageSource：`fileDataRepresentation()` 是带 EXIF 方向的 JPEG，
        // `from(data:)` 会读出来带上。这里不手工旋转。
        return source
    }
}

/// 一次拍照的在途状态：单飞标志 + 待 resume 的 continuation。
///
/// **`nonisolated` 是必须写的**，不是装饰：app target 用
/// `-default-isolation=MainActor` 编译，默认会把每个类型都隐式标成 `@MainActor`
/// ——那样 `nonisolated` 的拍照回调和取消处理器就都碰不到它了。只写
/// `@unchecked Sendable` 不够（实测：方法仍是 main actor-isolated）。
/// 类里的两个属性全部只经 `lock` 访问，没有任何一处裸露。
///
/// `finish` 是唯一对外收尾入口，**谁先取到谁负责 resume**，后到的拿到 nil 什么都不做
/// ——拍照回调和取消处理器可能同时到达，这样保证只 resume 一次。
nonisolated private final class PhotoCaptureSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data?, Never>?
    private var inFlight = false

    /// 占住单飞闸。false = 已经有一张在途，本次不要发拍照请求。
    func begin() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !inFlight else { return false }
        inFlight = true
        return true
    }

    func end() {
        lock.lock()
        inFlight = false
        lock.unlock()
    }

    func store(_ continuation: CheckedContinuation<Data?, Never>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func finish(with data: Data?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: data)
    }
}

// MARK: - 拍照回调

extension MagnifierViewModel: AVCapturePhotoCaptureDelegate {
    /// 显式 `nonisolated`：AVFoundation 在自己的队列上回调（头文件
    /// AVCapturePhotoOutput.h 写明 "not necessarily the main queue"）。app target
    /// 默认 `@MainActor` 隔离，不写这一句就是把一个要求主线程的方法交给后台队列去调，
    /// 真实设备上会踩隔离违规——而模拟器上永远测不到（没有相机）。
    ///
    /// 这里只做两件不跨隔离域的事：拿 JPEG 字节（`Data` 是 Sendable）、交给带锁的槽。
    /// 解析成 `OCRImageSource` 由 `capturePhoto()` 在它自己的隔离里做。
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            photoSlot.finish(with: nil)
            return
        }
        photoSlot.finish(with: data)
    }

    /// 收尾兜底。头文件写明这个回调 "always comes last"：拍照中途被中止
    /// （会话停了、相机被抢占、写盘失败）时 `didFinishProcessingPhoto` 可能根本不来，
    /// 那样单飞闸就永远占着，快门会一直停用。
    ///
    /// **无条件收尾，不要加 `error != nil` 的判断。** 成功路径上
    /// `didFinishProcessingPhoto` 已经把 continuation 取走了，槽是空的，`finish`
    /// 本身就是 no-op；而加上条件之后，唯一被改变的恰好是最坏那种情形：回调顺序若与
    /// 头文件不符（error 为 nil、`didFinishProcessingPhoto` 又没来），闸就永远不放，
    /// 用户看到的是一个转圈加一个再也按不动的快门，直到离开这个 tab。
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                                 error: Error?) {
        photoSlot.finish(with: nil)
    }
}
