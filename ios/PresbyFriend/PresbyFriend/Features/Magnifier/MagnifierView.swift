import SwiftUI
import AVFoundation

struct MagnifierView: View {
    @Environment(\.scenePhase) private var scenePhase
    /// 只读它的 `isPresenting`：阅读页盖上来时相机要停，理由见下面的 `.onChange`。
    @EnvironmentObject private var coordinator: ReaderLaunchCoordinator
    @StateObject private var vm = MagnifierViewModel()
    /// 按下快门后那一次拍照 + 交棒。存下句柄是为了离开页面时能取消它：
    /// `onDisappear` 会 `stopSession()`，此后拍照回调不再保证会来，取消才能让
    /// `capturePhoto()` 里在途的 continuation 立刻以「没拍到」收尾。
    @State private var captureTask: Task<Void, Never>?
    let onCapture: ((OCRImageSource) -> Void)?

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if isSimulator {
                // Simulator: no camera — show helpful placeholder
                VStack(spacing: 24) {
                    Spacer()
                    Image(systemName: "camera.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text(L10n.cameraError)
                        .font(.title2)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Text("Use a real device to magnify text with the camera. On the simulator, open the Read tab to paste text or pick a photo, then read it aloud.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 40)
                    Spacer()
                }
                .padding()
            } else if vm.cameraAccessGranted {
                // 预览。这里曾经叠着一层 `DataScannerViewController`（VisionKit 的实时文字），
                // 它自带一套 `AVCaptureSession`，和我们的会话抢同一颗后置摄像头。真机日志里
                // 我们的会话被以 reason 3 中断（`VideoDeviceInUseByAnotherClient`），预览层
                // 冻在最后一帧——**去掉它，这颗摄像头的所有者就只剩一个**。文字照旧能读：
                // 按快门 → OCR → 阅读页，只多按一下。
                CameraPreview(session: vm.session)
                    .ignoresSafeArea()

                // 原本这里还有一条「点文字就能读」的提示（`L10n.tapTextToRead`）。它指的是
                // 上面那层实时文字——层没了，提示照留着就是一句假话，所以一并去掉。
                // 键也删干净了：`L10n.tapTextToRead` 这个属性、6 个 `Localizable.strings`
                // 里的 `tap_text_to_read` 都不留，免得在文件里当孤儿（本工程已无引用）。

                // Controls overlay
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.title3)
                        Slider(value: $vm.zoomLevel, in: 1...8, step: 0.1)
                            .onChange(of: vm.zoomLevel) { _ in vm.applyZoom() }
                            .tint(.white)
                        Image(systemName: "plus.magnifyingglass")
                            .font(.title3)
                        Text(String(format: "%.1fx", vm.zoomLevel))
                            .font(.headline)
                            .frame(minWidth: 44)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal)

                    Button {
                        // 先取消上一个再覆盖句柄：上一个 Task 还挂着 `!Task.isCancelled`
                        // 交棒闸，句柄一丢就再没人能取消它，闸也就形同虚设。
                        captureTask?.cancel()
                        captureTask = Task {
                            // `capturePhoto()` 已经用单飞闸挡住重复点击；这里再挡一次
                            // 是取消时的交棒：本 Task 被取消（离开页面）就不再进阅读模式。
                            guard let source = await vm.capturePhoto(),
                                  !Task.isCancelled else { return }
                            onCapture?(source)
                        }
                    } label: {
                        ZStack {
                            if vm.isCapturing {
                                // 「已经按下去了」要有看得见的样子，否则第二下点击
                                // 和「什么都没发生」长得一模一样。
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 76, height: 76)
                        .background(Color.white.opacity(vm.isCapturing ? 0.15 : 0.25))
                        .overlay(Circle().stroke(Color.white, lineWidth: 4))
                        .clipShape(Circle())
                    }
                    // 会话还没跑起来时 `capturePhoto()` 会直接返回 nil（`session.isRunning`
                    // 闸），按钮却看起来能用——按下没有任何反应。那种窗口期里也要显示成
                    // 不可用，和「已经按下去了」一样是「看得见的状态」。
                    .disabled(vm.isCapturing || !vm.isSessionRunning)
                    .accessibilityLabel(L10n.shutter)

                    Button {
                        vm.toggleFlashlight()
                    } label: {
                        Image(systemName: vm.flashlightOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.title)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.bottom, 40)
                .padding(.horizontal)
            } else if let error = vm.cameraError {
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill").font(.system(size: 48))
                    Text(error)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                ProgressView()
            }
        }
        .task {
            guard !isSimulator else { return }
            await vm.requestAccess()
            // 权限流程走完时阅读页可能已经盖在上面了（分享一个 URL 冷启动进来就是这样），
            // 那样 `requestAccess` 刚起起来的会话会躲在阅读页背后——正是下面这条要挡的。
            // 只在阅读页真的开着时动手：正常路径下 `requestAccess` 自己已经把会话起好了，
            // 这里再 `setSessionActive(true)` 会重复添加同一路 input。
            if coordinator.isPresenting { vm.setSessionActive(false) }
        }
        .onDisappear {
            // 先取消在途的拍照，再停会话：停完之后拍照回调不再保证会来，靠取消
            // （`capturePhoto()` 的取消处理器）把那一按收尾。
            captureTask?.cancel()
            captureTask = nil
            vm.stopSession()
        }
        .onChange(of: coordinator.isPresenting) { presenting in
            // 阅读页是**盖上来**的一层，放大镜不会 `onDisappear`——没有这一条，相机会话
            // 会在整个阅读期间一直活着（真机实测阅读页上绿点常亮）。停/起两个方向的
            // 不对称与理由都在 `setSessionActive(_:)` 里。
            //
            // ⚠️ 这里**不照抄 `onDisappear` 那手 `captureTask?.cancel()`**：阅读页是在
            // OCR 出结果之后才呈现的，此刻那个 Task 正在收尾，取消它没有意义还可能把
            // `recordUse()` 那一段掐掉。要收的是会话，不是这一按。
            vm.setSessionActive(!presenting)
        }
        .onChange(of: scenePhase) { phase in
            // 只认 `.background`。`.inactive` 是「暂时不活跃」——下拉控制中心、来电
            // 横幅都会经过它，在那里关灯就成了「拉一下控制中心手电筒就灭」。
            //
            // 进后台时**系统会自己**中断并停掉会话（真机日志：`wasInterrupted reason=1`
            // 紧跟 `didStopRunning`，回前台时再由系统发 `interruptionEnded` 并
            // `didStartRunning` 起回来——所以会话那一侧不需要我们做任何事），
            // 但**灯不归它管**：`torchMode` 是设备自己的属性，会话停了它照样亮着。
            // 真机实测：按亮手电筒 → 最小化 App → 灯一直亮着，用户已经看不见 App 了，
            // 还得再打开它才能把灯关掉。
            guard phase == .background else { return }
            vm.turnOffFlashlight()
        }
    }
}

// MARK: - Camera Preview

/// 预览层的容器。**这个子类存在的唯一理由就是 `layerClass`。**
///
/// 改前的写法是：给一个裸 `UIView` 手动 `addSublayer` 一个 `AVCaptureVideoPreviewLayer`，
/// 再在 `updateUIView` 里把层的 frame 设成 `uiView.bounds`——**那是该层尺寸的唯一赋值点**。
/// 真机（iPhone 11 Pro Max）量出来的是：
/// ```
/// makeUIView      bounds=(0,0,0,0)  layerFrame=(0,0,0,0)
/// updateUIView #1 bounds=(0,0,0,0)  layerFrame=(0,0,0,0)
/// ```
/// `#1` 之后再没有 `#2`。两个原因叠在一起：
/// 1. 第一次被调用时 SwiftUI **还没排版**，`bounds` 就是 `.zero`；
/// 2. 之后 SwiftUI **不再调用它**——`CameraPreview` 的存储属性只有 `let session`，
///    body 重新求值时这个值没变，SwiftUI 比对后跳过更新。（当时 `didStartRunning`
///    确实触发了 body 重新求值，仍然没有第二次调用。）
///
/// 于是预览层永远停在 0 尺寸，屏幕上只剩背景色。而会话那一侧一切正常：
/// 同一份日志里 `session.isRunning` 与 `isSessionRunning` 都是 true、`wasInterrupted` 为零
/// ——**「会话在跑」和「看得见画面」是两件事，这条正是把它们分开的那道缝**。
///
/// 这个缺陷此前一直没被发现，是因为它上面压着一层全屏的 `DataScannerViewController`
/// （人家自带画面），把下面遮住了；把那层撤掉它才露出来。
///
/// `layerClass` 把预览层直接做成 view 的**背景层**：尺寸由 UIKit 跟着 view 走，不需要
/// 任何人记账，也不依赖 `updateUIView` 何时被调用。这是 Apple 在 AVCam 里的写法。
final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    /// `layerClass` 已经定死了背景层的类型，这一转换不会失败。
    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    /// 「会话开始跑」的观察者。连接是会话配上输入才建的，而**进页面时手机就是横的**
    /// 这一路里，那之后不会再有一次 `layoutSubviews`（bounds 没变过）——只靠
    /// `layoutSubviews` 会漏掉它，画面就一直是转着的。这条通知是那次补做的机会。
    private var didStartObserver: NSObjectProtocol?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            // 离开层级就把观察者摘掉：SwiftUI 重建这个 view 时不会替我们摘，
            // 而基于 block 的观察者不像 selector 那种会在对象释放时自动注销。
            if let didStartObserver { NotificationCenter.default.removeObserver(didStartObserver) }
            didStartObserver = nil
            return
        }
        if didStartObserver == nil, let session = previewLayer.session {
            didStartObserver = NotificationCenter.default.addObserver(
                forName: AVCaptureSession.didStartRunningNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                // 通知是会话在 `sessionQueue` 上跑起来之后发的，显式回主 actor 再碰
                // UIKit 对象；两个 target 的默认隔离不同（见 `isSessionRunning` 的注释），
                // 所以不靠隔离、统一显式回。
                Task { @MainActor in self?.applyInterfaceOrientation() }
            }
        }
        applyInterfaceOrientation()
    }

    /// 旋转会改变 view 的 bounds，所以这是「转屏了」的信号。
    ///
    /// 这条路在真机上量到过：横竖屏各转一次，`videoOrientation` 依次是
    /// `1 → 3`、`3 → 1`、`1 → 4`、`4 → 1`（`1` 竖屏，`3` 横屏 home 键在右，
    /// `4` 横屏 home 键在左）。
    override func layoutSubviews() {
        super.layoutSubviews()
        applyInterfaceOrientation()
    }

    /// 把「界面现在朝哪边」写进预览连接。
    ///
    /// 没有这一步，连接就停在 AVFoundation 自己的默认方向（竖屏）上。真机上量到的
    /// 就是这条：界面已经横过来了，连接的 `videoOrientation` 还是 `1`（竖屏）。于是
    /// 传感器画面照竖屏摆，**整幅画面转 90°**，而 `videoGravity = .resizeAspectFill`
    /// 又按错的方向去裁切，横竖屏看到的范围因此也不一样。
    ///
    /// 只有 iOS 17 起才有 `AVCaptureDevice.RotationCoordinator`（本项目的最低版本是
    /// 16.0），所以这里是 iOS 16 上唯一的做法：拿界面方向，手工写进连接。
    private func applyInterfaceOrientation() {
        guard let connection = previewLayer.connection,
              connection.isVideoOrientationSupported,
              let target = AVCaptureVideoOrientation(
                interfaceOrientation: window?.windowScene?.interfaceOrientation) else { return }
        // 值没变就不写：`layoutSubviews` 会被叫很多次，而给连接重复赋同一个值是白做。
        guard connection.videoOrientation != target else { return }
        connection.videoOrientation = target
    }
}

extension AVCaptureVideoOrientation {
    /// 界面方向 → 采集连接方向。**这是恒等映射，不是交叉映射**——别照着
    /// `UIDeviceOrientation` 那边的直觉改。
    ///
    /// 两份头文件对着读出来的（不靠记忆）：
    /// - UIKit 这边，`UIInterfaceOrientationLandscapeLeft` 的**定义**就是
    ///   `UIDeviceOrientationLandscapeRight`，`UIOrientation.h:39-40` 写着理由：
    ///   「rotating the device to the left requires rotating the content to the right」；
    ///   而 `UIDeviceOrientationLandscapeRight` 是「home button on the **left**」
    ///   （同文件 `:18`）。
    /// - AVFoundation 这边，`AVCaptureVideoOrientationLandscapeLeft` 是
    ///   「port on the **left**」（`AVCaptureDevice.h`，port 就是 home 键那一侧的接口）。
    ///
    /// 两边指的是**同一个物理边**，所以逐字相同。相机是后置（`MagnifierViewModel`
    /// 那三个 `position: .back`），也不存在前置镜像要换向的问题。
    ///
    /// `.unknown` 返回 nil = **不动连接**。那种状态下面向未知，猜一个方向只会把
    /// 已经正确的画面拧坏；而返回 `.portrait` 就是一种猜。
    init?(interfaceOrientation: UIInterfaceOrientation?) {
        switch interfaceOrientation {
        case .landscapeLeft:      self = .landscapeLeft
        case .landscapeRight:     self = .landscapeRight
        case .portrait:           self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        default:                  return nil
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}
