import SwiftUI
import VisionKit
import AVFoundation

struct MagnifierView: View {
    @StateObject private var vm = MagnifierViewModel()
    @State private var selectedText: String?
    @State private var dataScannerAccessGranted = false
    let onTextDetected: ((String) -> Void)?

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
                    Text("Use a real device to magnify text with the camera. On simulator, copy text and use \"Read Aloud\" from the Home tab.")
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
                            .onChange(of: vm.zoomLevel) { _, _ in vm.applyZoom() }
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
