import Foundation
import CoreGraphics
import Observation

/// Sucht das Board in mehreren Frames, mittelt die Kalibrierpunkte und erlaubt Feinjustierung per Hand.
@Observable
final class CalibrationModel {

    enum Phase: Equatable {
        case starting
        case searching(String)
        case locked
        case failed(String)
    }

    private(set) var phase: Phase = .starting
    /// Standbild, auf dem die Kalibrierung angezeigt und justiert wird.
    private(set) var snapshot: CGImage?
    private(set) var imageSize: CGSize = .zero
    private(set) var keypoints: BoardKeypoints?
    private(set) var calibration: BoardCalibration?
    private(set) var problem: String?
    private(set) var progress: Double = 0

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private var task: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
    }

    /// Effektive Auflösung als verständlicher Hinweis.
    var qualityHint: (text: String, good: Bool)? {
        guard let calibration else { return nil }
        let ppm = calibration.pixelsPerMillimeter
        if ppm >= 3 { return (String(format: "Sehr gute Auflösung (%.1f px/mm)", ppm), true) }
        if ppm >= 2 { return (String(format: "Gute Auflösung (%.1f px/mm)", ppm), true) }
        return (String(format: "Board klein im Bild (%.1f px/mm) – näher heran oder zoomen", ppm), false)
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in await self?.run() }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func retry() {
        snapshot = nil
        keypoints = nil
        calibration = nil
        problem = nil
        progress = 0
        start()
    }

    /// Punkt per Drag verschieben (Bildkoordinaten).
    func moveKeypoint(_ index: Int, to point: CGPoint) {
        guard var points = keypoints?.points, points.indices.contains(index) else { return }
        points[index] = CGPoint(x: min(max(point.x, 0), imageSize.width),
                                y: min(max(point.y, 0), imageSize.height))
        keypoints = BoardKeypoints(points: points)
        recompute()
    }

    private func recompute() {
        guard let keypoints else { return }
        problem = BoardCalibration.problem(with: keypoints, imageSize: imageSize)
        calibration = BoardCalibration(keypoints: keypoints, imageSize: imageSize)
    }

    private func run() async {
        phase = .starting
        guard await app.camera.prepare() else {
            phase = .failed(app.camera.state == .unauthorized
                            ? "Kein Kamerazugriff. Bitte in den iOS-Einstellungen erlauben."
                            : "Die Kamera ist nicht verfügbar.")
            return
        }
        app.camera.start()
        app.camera.setFocusLocked(false)
        app.motion.start()

        guard let detector = await app.makeDetector() else {
            phase = .failed(app.detectorError ?? "Die KI konnte nicht geladen werden.")
            return
        }

        phase = .searching("Suche Dartboard …")
        let needed = detector.cheapBoardCheck ? 5 : 2
        var samples: [BoardKeypoints] = []
        var size: CGSize = .zero
        var lastTimestamp: TimeInterval = -1

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(detector.cheapBoardCheck ? 250 : 400))
            guard let frame = app.camera.engine.latestFrame(), frame.timestamp != lastTimestamp else { continue }
            lastTimestamp = frame.timestamp
            if frame.size != size {
                samples.removeAll()
                size = frame.size
            }
            if !app.motion.isStill && !samples.isEmpty {
                samples.removeAll()
            }

            let detection: BoardDetection
            do {
                detection = try await detector.detectBoard(in: frame)
            } catch {
                phase = .searching(error.localizedDescription)
                continue
            }

            guard let found = detection.keypoints else {
                samples.removeAll()
                progress = 0
                phase = .searching(detection.foundCount > 0
                                   ? "\(detection.foundCount) von 4 Kalibrierpunkten erkannt – Board ganz ins Bild bringen"
                                   : "Suche Dartboard …")
                continue
            }
            if let message = BoardCalibration.problem(with: found, imageSize: frame.size) {
                samples.removeAll()
                progress = 0
                phase = .searching(message)
                continue
            }

            samples.append(found)
            if samples.count > 8 { samples.removeFirst(samples.count - 8) }
            progress = min(1, Double(samples.count) / Double(needed))
            phase = .searching("Board erkannt – bitte nicht bewegen …")

            guard samples.count >= needed,
                  let average = BoardKeypoints.robustAverage(of: samples, tolerance: GameSession.tolerance(forImageSize: size)),
                  average.inliers >= needed - 1
            else { continue }

            snapshot = FrameRenderer.shared.cgImage(from: frame.pixelBuffer, maxDimension: 1600)
            imageSize = size
            keypoints = average.keypoints
            recompute()
            if calibration != nil {
                phase = .locked
                return
            }
            samples.removeAll()
        }
    }
}
