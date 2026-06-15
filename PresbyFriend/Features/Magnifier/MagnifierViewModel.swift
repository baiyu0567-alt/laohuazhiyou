import AVFoundation
import SwiftUI

final class MagnifierViewModel: ObservableObject {
    @Published var zoomLevel: CGFloat = 2.0
    @Published var flashlightOn: Bool = false
    @Published var cameraAccessGranted: Bool = false
    @Published var cameraError: String?

    let session = AVCaptureSession()
    private let device: AVCaptureDevice? = {
        if let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
            return device
        }
        if let device = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            return device
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }()

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
            await MainActor.run { cameraError = L10n.cameraError }
        }
    }

    private func startSession() {
        guard let device else { return }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            if session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
            applyZoom()
        } catch {
            cameraError = "Failed to start camera"
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
        if let device, device.hasTorch, device.torchMode == .on {
            try? device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
        }
        flashlightOn = false
    }

    func detectedTextTapped(_ text: String) {
        // Handled by parent view — navigates to ReaderView
    }
}
