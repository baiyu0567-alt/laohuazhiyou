import AVFoundation
import SwiftUI
import Combine
import CoreGraphics
import OSLog

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
    /// 与其它文件同一套构造方式（`ReadTabView`、`PasteControlView`）：subsystem 跟着
    /// `Bundle.main` 走。本文件同时编译进分享扩展，不在扩展里冒充 App 的标识。
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.presbyfriend",
        category: "magnifier")

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
    /// 值也由会话自己的通知驱动——**中断**（相机被别人抢走、来电、退到后台）不经过
    /// `stopSession()`，只在起停两处写它会让它停在 true。见 `observeSessionState()`。
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

    /// 会话代次。`startSession()`、`stopSession()`、以及会话**真的停下**时
    /// （`didStopRunningNotification`，见 `observeSessionState()`）各自增一次。
    ///
    /// **为什么需要它**：`startSession()` 把 `startRunning()` 丢到 `sessionQueue` 上阻塞执行，收尾
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

    /// 全部会话操作（配置 + `startRunning()` / `stopRunning()`）**唯一**的执行场所。
    ///
    /// **为什么必须是串行、而且是唯一**：`AVCaptureSession` 不支持在多个线程上并发做这些事
    /// ——Apple 自己的 AVCam 样例就为此专开一把 sessionQueue。以前 `startRunning()` 走的是
    /// **全局并发**队列、`stopRunning()` 与配置走的是调用者线程（主 actor），三者互不串行：
    /// 用户进放大镜 tab 后 `startRunning()` 还在阻塞、立刻离开触发 `stopRunning()`，两者就真的
    /// 撞在同一个 session 上（台账「真机检查表第 13 行」）。
    ///
    /// 一把串行队列同时给到两个性质：三者互斥，且 FIFO 保证「先 stop 再 start」的顺序——离开
    /// tab 又马上回来时正是这个顺序。顺带把主线程从一次阻塞调用（`stopRunning()`）里解放出来。
    ///
    /// 与 `TextRecognitionService.queue`、`photoSlot` 的锁都无关，是独立一把：前者串行化的是
    /// 整段 Vision 请求（首次预热占住 28–34s，见 `prewarm()` 注释），后者保护的是两个小值。
    /// `qos` 显式给 `.userInitiated`，与改前 `DispatchQueue.global(qos: .userInitiated)` 一致，
    /// 不要让起相机的延迟退化。
    private let sessionQueue = DispatchQueue(label: "com.presbyfriend.magnifier.session",
                                             qos: .userInitiated)

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

    /// 会话通知的观察者句柄。见 `observeSessionState()`。
    private var sessionObservers: [NSObjectProtocol] = []

    override init() {
        super.init()
        observeSessionState()
        observeSessionDiagnostics()
    }

    /// 让 `isSessionRunning` 跟着会话的**真实**状态走。
    ///
    /// **为什么只在 `startSession()` / `stopSession()` 里写它不够**：会话停下来有两条
    /// 路，只有一条经过我们的代码。`stopSession()` 是**我们要停**；另一条是会话**被
    /// 中断**——相机被另一个 `AVCaptureSession` 抢走（`wasInterruptedNotification` 的
    /// `AVCaptureSessionInterruptionReasonKey` 为 3，`VideoDeviceInUseByAnotherClient`）、
    /// 来电、退到后台、系统压力。中断不经过 `stopSession()`，`isSessionRunning` 于是
    /// 停在 true。
    ///
    /// 真机日志（iPhone 11 Pro Max）实测到分叉的那一刻，正是用户拖缩放滑杆时：
    /// ```
    /// PFDIAG [zoom] level=2.2 session.isRunning=false isSessionRunning=true
    /// ```
    /// 后果是他看到的那样：预览层冻在最后一帧，而快门照常显示可用、滑杆照常响应
    /// 手势——「页面是活的，画面不动」。
    ///
    /// `didStartRunning` / `didStopRunning` 是 AVFoundation 在会话**真的**起停那一刻
    /// 发的，正是 `isSessionRunning` 想表达的那件事，所以用它俩而不是自己推断。中断时
    /// `didStopRunning` 会跟着 `wasInterrupted` 一起来（真机日志顺序：
    /// `wasInterrupted` → `didStopRunning`），所以不必单独盯 `wasInterrupted`。
    ///
    /// `didStopRunning` 里那手自增，与 `stopSession()` 里的是同一手、同一个道理：作废
    /// 在途的那次 `startSession()` 收尾（见 `sessionGeneration`），否则它会在这之后把
    /// `isSessionRunning` 写回 true——而那个值恰恰是这个函数要断开的东西。这条正是
    /// `sessionGeneration` 注释里说的那次竞态，只是触发者除了 `stopSession()` 还有中断。
    private func observeSessionState() {
        let center = NotificationCenter.default
        for (name, running) in [
            (AVCaptureSession.didStartRunningNotification, true),
            (AVCaptureSession.didStopRunningNotification, false),
        ] {
            sessionObservers.append(center.addObserver(
                forName: name, object: session, queue: .main
            ) { [weak self] _ in
                // 显式回 `@MainActor` 再写 `@Published`：两个 target 的默认隔离不同
                // （见 `isSessionRunning` 的注释），所以不押在默认隔离上——与
                // `startSession()` 收尾处同一写法。
                Task { @MainActor in
                    guard let self else { return }
                    if !running { self.sessionGeneration += 1 }
                    self.isSessionRunning = running
                    // 会话真的跑起来了，之前记下的错误就是**过期的**，必须清掉。
                    //
                    // 不清的后果不是「留一句多余的提示」：`MagnifierView` 里那条错误分支
                    // 排在预览分支**之前**（理由见那里的注释），于是「起失败过、后来起成了」
                    // 会变成一块再也退不出去的报错界面——画面就在下面而用户看不到。
                    // 清在这里而不是 `startSession()` 开头：只有「真的跑起来了」才谈得上
                    // 上一次的错误已经作废，开头清等于自己把正在发生的失败抹掉。
                    if running { self.cameraError = nil }
                }
            })
        }
    }

    /// ⚠️【临时诊断·device-test-noshare】随分支作废。
    /// 这一轮要看的是：去掉 `DataScannerViewController` 之后，`wasInterrupted`（尤其
    /// reason 3）还会不会来。若不来了，就等于反向坐实了诊断。修好之后整段删除——
    /// `observeSessionState()` 本身不带任何日志。
    private func observeSessionDiagnostics() {
        let center = NotificationCenter.default
        let names: [(Notification.Name, String)] = [
            (AVCaptureSession.wasInterruptedNotification, "wasInterrupted"),
            (AVCaptureSession.interruptionEndedNotification, "interruptionEnded"),
            (AVCaptureSession.didStartRunningNotification, "didStartRunning"),
            (AVCaptureSession.didStopRunningNotification, "didStopRunning"),
            (AVCaptureSession.runtimeErrorNotification, "runtimeError"),
        ]
        for (name, label) in names {
            sessionObservers.append(center.addObserver(
                forName: name, object: session, queue: .main
            ) { note in
                print("PFDIAG [session] \(label) userInfo=\(String(describing: note.userInfo))")
            })
        }
    }

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

    /// 让会话跟着「放大镜这一屏是否真的可见」起停。
    ///
    /// **为什么需要它**：阅读页是 ZStack 里**盖上来**的一层（`PresbyFriendApp.swift` 的
    /// `coordinator.isPresenting` 那段），不是 push——放大镜**不会** `onDisappear`，
    /// 那条 `stopSession()` 永远不会被调到。真机实测（2026-09-24，iPhone 11 Pro Max）：
    /// 阅读页上系统相机绿点**一直亮着**，会话全程活着。而阅读正是本 App 的主场景
    /// （老花眼用户一读就是几分钟），那期间白耗电，绿点也容易让用户以为还在拍。
    ///
    /// **两个方向刻意不对称**：
    /// - **起：必须先挡重复。** `startSession()` 会把同一个 device 的 input 再加一份，
    ///   而 `AVCaptureSession` 不支持同一路输入叠两份。`isSessionRunning` 的写入又是
    ///   异步的（`startRunning()` 返回后才置真），光靠它挡不住这个窗口。
    /// - **停：不设闸，一律照停。** 会话可能正起在半路（此时 `isSessionRunning` 还是
    ///   false），那种情况**也该停**——`stopSession()` 里那手代次自增正是用来作废在途
    ///   那次启动的（见 `sessionGeneration`）。它在会话没跑时调同样安全：
    ///   `photoSlot.finish` 对空槽只做一次判空，`turnOffFlashlight()` 自带
    ///   `torchMode == .on` 前置。
    func setSessionActive(_ active: Bool) {
        if active {
            guard cameraAccessGranted, !isSessionRunning else { return }
            startSession()
        } else {
            stopSession()
        }
    }

    private func startSession() {
        guard let device else { return }
        // 代次在主 actor 上自增：`stopSession()` 也在这里自增，两者的读写必须同域
        // （见 `sessionGeneration` 的注释）。
        sessionGeneration += 1
        let token = sessionGeneration
        print("PFDIAG [lifecycle] startSession token=\(token)")
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                // 配置与 start/stop 同处这把串行队列，理由见 `sessionQueue` 的注释。
                self.session.beginConfiguration()
                if self.session.canAddInput(input) { self.session.addInput(input) }
                // 在 commitConfiguration 之前挂上输出：配置提交后再改要另开一次配置块。
                if self.session.canAddOutput(self.photoOutput) { self.session.addOutput(self.photoOutput) }
                self.session.commitConfiguration()
                self.session.startRunning()
                print("PFDIAG [lifecycle] startRunning returned, isRunning=\(self.session.isRunning)")
                // 回主线程再写 `@Published`：这段闭包跑在 `sessionQueue` 上（`startRunning()`
                // 会阻塞，不能占住主线程），在这里直接赋值就是从后台线程发布一次 SwiftUI 变更。
                // 两个 target 的默认隔离不同（见 `isSessionRunning` 的注释），所以不靠隔离，
                // 统一显式回 `@MainActor` 再写。
                Task { @MainActor in
                    guard self.sessionGeneration == token else { return }
                    self.isSessionRunning = true
                }
            } catch {
                // `cameraError` 是 `@Published`，同样要回主 actor 写（理由同上）。
                Task { @MainActor in self.cameraError = L10n.cameraError }
            }
        }
        applyZoom()
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

    /// 关手电筒，并把 `flashlightOn` 归位。
    ///
    /// **会话停了不等于灯灭了。** `torchMode` 是设备自己的属性：App 进后台时系统会
    /// 中断并停掉会话（真机日志：`wasInterrupted reason=1` 紧跟 `didStopRunning`），
    /// 灯却照样亮着——用户已经看不见 App 了，灯还亮着，只能再打开 App 去关。
    /// 真机实测就是如此：按亮手电筒 → 最小化 App → 灯一直亮。
    ///
    /// 闸放在**设备**上而不是 `flashlightOn` 上：`stopSession()` 一直这么写，
    /// 而设备的真实状态才是这件事的依据。
    ///
    /// **`do/catch` 在这里不是风格问题，是必须的。** 这里原先是
    /// `try? device.lockForConfiguration()` 紧跟一行**无条件**的
    /// `device.torchMode = .off`。`try?` 只把「锁定失败」变成 nil，**不会跳过下一行**
    /// ——锁没拿到，赋值照执行。而 `AVCaptureDevice.h:1127` 写得很明白：
    /// `-setTorchMode:` **在未持有 `lockForConfiguration:` 的情况下抛
    /// `NSGenericException`**。那是 ObjC 异常，Swift 侧 `try?` 接不住，直接终止进程。
    ///
    /// 锁失败不是理论情形：它恰恰是这台设备正被别的东西占着时会发生的事，而这个函数
    /// 被叫到的两个场合（离开放大镜页、App 进后台）**都是**系统正在动这颗摄像头的
    /// 时候。本文件另外两处拿设备锁的地方（`applyZoom()`、`toggleFlashlight()`）
    /// 本来就是 `do/catch`，只有这一处是 `try?`。
    func turnOffFlashlight() {
        flashlightOn = false
        guard let device, device.hasTorch, device.torchMode == .on else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
        } catch {
            // 锁拿不到就关不了灯——没有 API 能绕过设备锁，这条路上没有备用手段。
            // 但**必须留痕**：这一路失败的样子和「修好了」在用户眼里一模一样
            // （灯还亮着），静默吞掉就等于下次还得从零查一遍。
            Self.logger.error("Torch off failed, device lock unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    func stopSession() {
        print("PFDIAG [lifecycle] stopSession (isRunning=\(session.isRunning))")
        // 与 `startRunning()` 走**同一把**串行队列：改前它是在当前线程（主 actor）同步调用的，
        // 而 `startRunning()` 在全局**并发**队列上——两者可以真的重叠，那是 `AVCaptureSession`
        // 不支持的用法（见 `sessionQueue` 的注释）。顺带把主线程从这次阻塞调用里解放出来。
        sessionQueue.async { [weak self] in self?.session.stopRunning() }
        // 会话停了，拍照回调就不再保证会来。不在这里把在途的那一按收掉的话，
        // 它永远不完成，快门会一直停在忙碌态（`isCapturing` 为真）再也按不动。
        photoSlot.finish(with: nil)
        // 关灯这一步与「App 进后台」共用同一份实现（`turnOffFlashlight()`）：两处要做的
        // 事一模一样，分开写迟早只改一处。
        turnOffFlashlight()
        // 与 `isSessionRunning = false` 同处自增：作废在途的那次 `startSession()` 收尾，
        // 否则它会在会话已停之后把 `isSessionRunning` 写回 true（见 `sessionGeneration`）。
        sessionGeneration += 1
        isSessionRunning = false
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
