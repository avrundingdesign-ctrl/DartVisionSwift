import Foundation
import UIKit

// MARK: - Pipeline-Ergebnis

struct PipelineResult {
    let keypoints: [DetectedKeypoint]
    let darts: [(position: CGPoint, score: DartScore, confidence: Float)]
}

// MARK: - Errors

enum PipelineError: Error, LocalizedError {
    case homographyFailed
    case notEnoughKeypoints(found: Int)
    case imageConversionFailed

    var errorDescription: String? {
        switch self {
        case .homographyFailed:
            return "Homographie konnte nicht berechnet werden"
        case .notEnoughKeypoints(let n):
            return "Nur \(n) von 4 Board-Keypoints erkannt"
        case .imageConversionFailed:
            return "Bild konnte nicht konvertiert werden"
        }
    }
}

// MARK: - Image Pipeline

/// Orchestriert die gesamte On-Device-Verarbeitung.
/// Ersetzt V4_Server.py + V4_Warp_Image_keypoints.py → Process_Start_Main()
class ImagePipeline {

    private let yolo: YOLOInference
    private var cachedKeypoints: [DetectedKeypoint]?
    private var cachedHomography: [Double]?

    // MARK: - Init

    init() throws {
        yolo = try YOLOInference()
    }

    // MARK: - Hauptfunktion

    /// Verarbeitet ein Kamerabild und gibt erkannte Darts mit Scores zurück.
    ///
    /// Ablauf (identisch zu Process_Start_Main in Python):
    /// 1. Board-Keypoints erkennen (oder cached verwenden)
    /// 2. Homographie berechnen
    /// 3. Darts erkennen
    /// 4. Dart-Koordinaten transformieren
    /// 5. Score berechnen
    func process(image: CGImage, existingKeypoints: [DetectedKeypoint]? = nil) throws -> PipelineResult {

        // ─── 1. Keypoints ───
        let keypoints: [DetectedKeypoint]
        if let existing = existingKeypoints, existing.count == 4 {
            keypoints = existing
        } else if let cached = cachedKeypoints, cached.count == 4 {
            keypoints = cached
        } else {
            keypoints = try yolo.detectBoardKeypoints(in: image)
            if keypoints.count < 4 {
                throw PipelineError.notEnoughKeypoints(found: keypoints.count)
            }
            cachedKeypoints = keypoints
        }

        // ─── 2. Homographie ───
        guard let H = BoardWarper.computeHomography(from: keypoints) else {
            throw PipelineError.homographyFailed
        }
        cachedHomography = H

        // ─── 3. Darts erkennen ───
        let detectedDarts = try yolo.detectDarts(in: image)

        if detectedDarts.isEmpty {
            return PipelineResult(keypoints: keypoints, darts: [])
        }

        // ─── 4. Transformieren + 5. Score berechnen ───
        let transformedDarts = BoardWarper.transformDarts(detectedDarts, homography: H)

        let results = transformedDarts.map { dart in
            let score = DartScorer.getScore(at: dart.position)
            return (position: dart.position, score: score, confidence: dart.confidence)
        }

        return PipelineResult(keypoints: keypoints, darts: results)
    }

    // MARK: - Keypoint-Management

    /// Keypoints zurücksetzen (z.B. wenn sich die Kameraposition ändert)
    func resetKeypoints() {
        cachedKeypoints = nil
        cachedHomography = nil
    }

    /// Aktuelle gecachte Keypoints
    var currentKeypoints: [DetectedKeypoint]? {
        return cachedKeypoints
    }

    /// Keypoints manuell setzen (z.B. vom letzten Frame übernommen)
    func setKeypoints(_ keypoints: [DetectedKeypoint]) {
        cachedKeypoints = keypoints
        if keypoints.count == 4 {
            cachedHomography = BoardWarper.computeHomography(from: keypoints)
        }
    }
}
