import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import CoreMedia

nonisolated enum CameraError: LocalizedError {
    case unauthorized
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Kein Kamerazugriff. Bitte in den Einstellungen erlauben."
        case .unavailable: return "Kamera nicht verfügbar."
        }
    }
}

/// Kapselt AVCaptureSession und den Video-Output. Läuft komplett auf eigenen Queues;
/// statt alle 4 s ein Foto zu schießen, steht hier jederzeit das neueste Videobild bereit.
nonisolated final class CaptureEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    nonisolated struct Info: Sendable {
        /// Zoomstufen für die Anzeige (1 = Weitwinkel).
        let zoomOptions: [CGFloat]
        let resolution: CGSize
    }

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "dartvision.capture.session")
    private let videoQueue = DispatchQueue(label: "dartvision.capture.video", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let lock = NSLock()

    private var latestBuffer: CVPixelBuffer?
    private var latestTimestamp: TimeInterval = 0
    private var currentDevice: AVCaptureDevice?
    private var baseZoom: CGFloat = 1
    private var info: Info?

    var device: AVCaptureDevice? {
        lock.lock()
        defer { lock.unlock() }
        return currentDevice
    }

    // MARK: - Konfiguration

    func configure() async throws -> Info {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Info, Error>) in
            sessionQueue.async {
                do {
                    continuation.resume(returning: try self.configureOnQueue())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configureOnQueue() throws -> Info {
        if let info { return info }

        let types: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera
        ]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .back)
        guard let device = discovery.devices.first else { throw CameraError.unavailable }
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraError.unavailable
        }
        session.addInput(input)

        // 4K liefert für die Dart-Spitzen deutlich mehr Pixel pro mm als 1080p.
        if session.canSetSessionPreset(.hd4K3840x2160) {
            session.sessionPreset = .hd4K3840x2160
        } else if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        }

        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            throw CameraError.unavailable
        }
        session.addOutput(videoOutput)
        // Erst committen – das Preset setzt Format und Bildrate des Geräts zurück.
        session.commitConfiguration()

        // Bei Mehrfachkameras ist Zoom 1.0 das Ultraweitwinkel – wir starten auf dem Weitwinkel.
        let hasUltraWide = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
        if hasUltraWide, let firstSwitch = device.virtualDeviceSwitchOverVideoZoomFactors.first {
            baseZoom = CGFloat(truncating: firstSwitch)
        } else {
            baseZoom = 1
        }

        try device.lockForConfiguration()
        device.videoZoomFactor = clampZoom(baseZoom, for: device)
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        // 15 fps reichen völlig und sparen Akku/Wärme.
        let fifteen = CMTime(value: 1, timescale: 15)
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameDuration <= fifteen && $0.maxFrameDuration >= fifteen }) {
            device.activeVideoMinFrameDuration = fifteen
            device.activeVideoMaxFrameDuration = fifteen
        }
        device.unlockForConfiguration()

        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let maxUserZoom = min(device.maxAvailableVideoZoomFactor / baseZoom, 5)
        let candidates: [CGFloat] = [1, 1.5, 2, 3]
        let zoomOptions = candidates.filter { $0 <= maxUserZoom }
        let result = Info(zoomOptions: zoomOptions.isEmpty ? [1] : zoomOptions,
                          resolution: CGSize(width: Int(dimensions.width), height: Int(dimensions.height)))

        lock.lock()
        currentDevice = device
        lock.unlock()
        info = result
        return result
    }

    private func clampZoom(_ factor: CGFloat, for device: AVCaptureDevice) -> CGFloat {
        min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
    }

    // MARK: - Steuerung

    func start() {
        sessionQueue.async {
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.lock.lock()
            self.latestBuffer = nil
            self.lock.unlock()
        }
    }

    /// Dreht die Videobilder so, dass das Board aufrecht ist (wie die Trainingsbilder).
    func setRotation(_ angle: CGFloat) {
        sessionQueue.async {
            guard let connection = self.videoOutput.connection(with: .video),
                  connection.isVideoRotationAngleSupported(angle),
                  connection.videoRotationAngle != angle
            else { return }
            connection.videoRotationAngle = angle
            self.lock.lock()
            self.latestBuffer = nil
            self.lock.unlock()
        }
    }

    /// Zoom relativ zum Weitwinkel (1 = 1×).
    func setZoom(_ userZoom: CGFloat) {
        sessionQueue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = self.clampZoom(self.baseZoom * userZoom, for: device)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    /// Fokus nach der Kalibrierung festhalten – verhindert Pumpen, wenn jemand vor dem Board steht.
    func setFocusLocked(_ locked: Bool) {
        sessionQueue.async {
            guard let device = self.device else { return }
            let mode: AVCaptureDevice.FocusMode = locked ? .locked : .continuousAutoFocus
            guard device.isFocusModeSupported(mode) else { return }
            do {
                try device.lockForConfiguration()
                device.focusMode = mode
                device.unlockForConfiguration()
            } catch {}
        }
    }

    // MARK: - Frames

    func latestFrame() -> AnalysisFrame? {
        lock.lock()
        defer { lock.unlock() }
        guard let latestBuffer else { return nil }
        return AnalysisFrame(pixelBuffer: latestBuffer, timestamp: latestTimestamp)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        lock.lock()
        latestBuffer = buffer
        latestTimestamp = timestamp
        lock.unlock()
    }
}
