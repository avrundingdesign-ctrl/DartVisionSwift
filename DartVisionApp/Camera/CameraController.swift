import Foundation
import AVFoundation
import Observation
import CoreGraphics

/// UI-seitiger Zustand der Kamera (Berechtigung, Zoom, Ausrichtung).
@Observable
final class CameraController {

    enum State: Equatable {
        case idle
        case unauthorized
        case unavailable
        case ready
        case running
    }

    private(set) var state: State = .idle
    private(set) var zoomOptions: [CGFloat] = [1]
    private(set) var zoom: CGFloat = 1

    @ObservationIgnored let engine = CaptureEngine()
    @ObservationIgnored private var coordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var captureObservation: NSKeyValueObservation?
    @ObservationIgnored private var previewObservation: NSKeyValueObservation?
    @ObservationIgnored private weak var previewLayer: AVCaptureVideoPreviewLayer?

    var isAvailable: Bool { state == .ready || state == .running }

    /// Fragt die Berechtigung ab und konfiguriert die Session (einmalig).
    func prepare() async -> Bool {
        if isAvailable { return true }
        var granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard granted else {
            state = .unauthorized
            return false
        }
        do {
            let info = try await engine.configure()
            zoomOptions = info.zoomOptions
            state = .ready
            installRotationCoordinator()
            return true
        } catch {
            state = .unavailable
            return false
        }
    }

    func start() {
        guard isAvailable else { return }
        engine.start()
        state = .running
    }

    func stop() {
        engine.stop()
        if state == .running { state = .ready }
    }

    func setZoom(_ value: CGFloat) {
        zoom = value
        engine.setZoom(value)
    }

    func setFocusLocked(_ locked: Bool) {
        engine.setFocusLocked(locked)
    }

    /// Wird von der Vorschau aufgerufen, damit auch deren Ausrichtung stimmt.
    func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {
        previewLayer = layer
        installRotationCoordinator()
    }

    // MARK: - Ausrichtung

    /// Der RotationCoordinator liefert über die Schwerkraft den Winkel, mit dem das Bild
    /// waagerecht ist – egal ob das iPhone hochkant oder quer am Stativ hängt.
    private func installRotationCoordinator() {
        guard let device = engine.device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        self.coordinator = coordinator

        let engine = self.engine
        captureObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { @Sendable (_, change) in
            guard let angle = change.newValue else { return }
            engine.setRotation(angle)
        }

        if previewLayer != nil {
            previewObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { @Sendable [weak self] (_, change) in
                guard let angle = change.newValue else { return }
                Task { @MainActor [weak self] in
                    self?.applyPreviewAngle(angle)
                }
            }
        } else {
            previewObservation = nil
        }
    }

    private func applyPreviewAngle(_ angle: CGFloat) {
        guard let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}
