import Foundation
import CoreGraphics
import CoreVideo

/// Ein Kamerabild für die Analyse – bereits aufrecht gedreht (Rotation macht die Capture-Pipeline).
nonisolated struct AnalysisFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let timestamp: TimeInterval

    var size: CGSize {
        CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
    }
}

/// Ergebnis der Board-Erkennung.
nonisolated struct BoardDetection: Sendable {
    /// Alle 4 Punkte gefunden → Keypoints, sonst `nil`.
    var keypoints: BoardKeypoints?
    /// Konfidenz je Punkt (top, right, bottom, left); 0 = nicht gefunden.
    var confidences: [Double]
    /// Teilweise gefundene Punkte (für Sichtbarkeitsprüfung), Reihenfolge wie `confidences`.
    var partialPoints: [CGPoint?]

    static let none = BoardDetection(keypoints: nil, confidences: [0, 0, 0, 0], partialPoints: [nil, nil, nil, nil])

    var foundCount: Int { partialPoints.compactMap { $0 }.count }

    /// Wie viele Kalibrierpunkte stimmen mit der bestehenden Kalibrierung überein?
    func matchingPoints(with keypoints: BoardKeypoints, tolerance: CGFloat) -> Int {
        zip(partialPoints, keypoints.points).filter { found, expected in
            guard let found else { return false }
            return hypot(found.x - expected.x, found.y - expected.y) <= tolerance
        }.count
    }
}

nonisolated enum DetectionBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case onDevice
    case server

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDevice: return "Auf dem iPhone"
        case .server: return "Server"
        }
    }
}

nonisolated struct DetectorTuning: Equatable, Sendable {
    /// Minimale Konfidenz, ab der Erkennungen überhaupt zurückgegeben werden.
    var minConfidence: Double = 0.25
    /// Wie stark für die Dart-Erkennung maximal auf das Board gezoomt wird (1 = aus).
    /// Experimentell: hilft nur, solange die Darts nicht deutlich größer wirken als im Training.
    var maxBoardZoom: Double = 1.0
}

nonisolated enum DetectionError: LocalizedError {
    case modelMissing
    case invalidModelOutput
    case pixelBufferFailed
    case encodingFailed
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .modelMissing: return "Die KI-Modelle fehlen im App-Bundle."
        case .invalidModelOutput: return "Unerwartete Ausgabe des KI-Modells."
        case .pixelBufferFailed: return "Bild konnte nicht vorbereitet werden."
        case .encodingFailed: return "Bild konnte nicht komprimiert werden."
        case .network(let message): return "Verbindungsfehler: \(message)"
        case .server(let message): return "Server-Fehler: \(message)"
        }
    }
}

/// Gemeinsame Schnittstelle für die KI – lokal (CoreML) oder auf dem Server.
nonisolated protocol DartDetector: AnyObject, Sendable {
    var displayName: String { get }
    /// Analyse-Takt: so lange wird zwischen zwei Frames mindestens gewartet.
    var preferredInterval: TimeInterval { get }
    /// Ob eine Board-Prüfung günstig genug für jeden leeren Frame ist.
    var cheapBoardCheck: Bool { get }

    func detectBoard(in frame: AnalysisFrame) async throws -> BoardDetection
    func detectDarts(in frame: AnalysisFrame, calibration: BoardCalibration) async throws -> [DartCandidate]
    func updateTuning(_ tuning: DetectorTuning) async
}
