import SwiftUI
import VisionKit
import AVFoundation

struct MagnifierView: View {
    @StateObject private var vm = MagnifierViewModel()
    @State private var selectedText: String?
    @State private var dataScannerAccessGranted = false
    /// 按下快门后那一次拍照 + 交棒。存下句柄是为了离开页面时能取消它：
    /// `onDisappear` 会 `stopSession()`，此后拍照回调不再保证会来，取消才能让
    /// `capturePhoto()` 里在途的 continuation 立刻以「没拍到」收尾。
    @State private var captureTask: Task<Void, Never>?
    let onTextDetected: ((String) -> Void)?
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
                // Camera preview + Live Text overlay
                CameraPreview(session: vm.session)
                    .ignoresSafeArea()

                if dataScannerAccessGranted {
                    LiveTextScanner { text in
                        onTextDetected?(text)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                }

                // Tap hint
                VStack {
                    Spacer().frame(height: 100)
                    Text(L10n.tapTextToRead)
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    Spacer()
                }

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
            dataScannerAccessGranted = DataScannerViewController.isSupported &&
                                       DataScannerViewController.isAvailable
        }
        .onDisappear {
            // 先取消在途的拍照，再停会话：停完之后拍照回调不再保证会来，靠取消
            // （`capturePhoto()` 的取消处理器）把那一按收尾。
            captureTask?.cancel()
            captureTask = nil
            vm.stopSession()
        }
    }
}

// MARK: - Camera Preview

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        context.coordinator.previewLayer = preview
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
        context.coordinator.previewLayer?.session = session
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - Live Text Scanner

struct LiveTextScanner: UIViewControllerRepresentable {
    let onTextTap: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onTextTap: onTextTap) }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onTextTap: (String) -> Void

        init(onTextTap: @escaping (String) -> Void) {
            self.onTextTap = onTextTap
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .text(let text) = item {
                onTextTap(text.transcript)
            }
        }
    }
}
