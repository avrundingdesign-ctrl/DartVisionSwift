import Foundation
import CoreML
import CoreGraphics
import CoreVideo

/// KI direkt auf dem iPhone (CoreML, Neural Engine). Nutzt die gebündelten YOLO11-Pose-Modelle
/// `Board` (4 Kalibrierpunkte) und `Darts` (Dartspitzen).
///
/// Verbesserungen gegenüber der ersten Portierung:
/// - Letterbox statt Verzerren (wie im Training),
/// - Dart-Erkennung auf einem Ausschnitt rund ums Board (mehr Pixel pro mm),
/// - Duplikatfilter über den Spitzenabstand statt nur über Box-Überlappung,
/// - Ausgabe-Tensor wird über Shape/Strides gelesen (robust gegen Layout-Änderungen).
actor OnDeviceDetector: DartDetector {

    nonisolated let displayName = "KI auf dem iPhone"
    nonisolated let preferredInterval: TimeInterval = 0.3
    nonisolated let cheapBoardCheck = true

    private let boardModel: MLModel
    private let dartsModel: MLModel
    private let boardInput: ModelInput
    private let dartsInput: ModelInput
    private let renderer = FrameRenderer()
    private var tuning = DetectorTuning()

    nonisolated private struct ModelInput: Sendable {
        let name: String
        let size: Int
    }

    nonisolated static var modelsAvailable: Bool {
        modelURL(named: "Board") != nil && modelURL(named: "Darts") != nil
    }

    init() throws {
        guard let boardURL = Self.modelURL(named: "Board"),
              let dartsURL = Self.modelURL(named: "Darts")
        else { throw DetectionError.modelMissing }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let board = try MLModel(contentsOf: boardURL, configuration: configuration)
        let darts = try MLModel(contentsOf: dartsURL, configuration: configuration)
        boardModel = board
        dartsModel = darts
        boardInput = try Self.imageInput(of: board)
        dartsInput = try Self.imageInput(of: darts)
    }

    func updateTuning(_ tuning: DetectorTuning) async {
        self.tuning = tuning
    }

    // MARK: - Board

    func detectBoard(in frame: AnalysisFrame) async throws -> BoardDetection {
        let full = CGRect(origin: .zero, size: frame.size)
        let (input, transform) = try renderer.letterbox(frame.pixelBuffer, roi: full, size: boardInput.size)
        let output = try predict(boardModel, input: boardInput, buffer: input)
        let detections = try YOLOPoseDecoder.decode(output, numClasses: 4, minScore: 0.3)
        let best = YOLOPoseDecoder.bestPerClass(detections, numClasses: 4)

        // Klassenreihenfolge des Modells: 0 TOP, 1 Right, 2 Bottom, 3 Left
        let points: [CGPoint?] = best.map { $0.map { transform.toImage($0.keypoint) } }
        let confidences = best.map { Double($0?.score ?? 0) }
        let found = points.compactMap { $0 }
        let keypoints = found.count == 4 ? BoardKeypoints(points: found) : nil
        return BoardDetection(keypoints: keypoints, confidences: confidences, partialPoints: points)
    }

    // MARK: - Darts

    func detectDarts(in frame: AnalysisFrame, calibration: BoardCalibration) async throws -> [DartCandidate] {
        let region = Self.dartRegion(calibration: calibration, frameSize: frame.size,
                                     inputSize: CGFloat(dartsInput.size), maxZoom: CGFloat(tuning.maxBoardZoom))
        let (input, transform) = try renderer.letterbox(frame.pixelBuffer, roi: region, size: dartsInput.size)
        let output = try predict(dartsModel, input: dartsInput, buffer: input)
        let raw = try YOLOPoseDecoder.decode(output, numClasses: 1, minScore: Float(tuning.minConfidence))

        // Spitzen näher als ~3 mm sind derselbe Dart.
        let modelPixelsPerMM = calibration.pixelsPerMillimeter * Double(transform.scale)
        let tipDistance = CGFloat(max(3.0 * modelPixelsPerMM, 3.0))
        let unique = YOLOPoseDecoder.suppressDuplicates(raw, keypointDistance: tipDistance, iouThreshold: 0.85)

        return unique.compactMap { detection in
            let imagePoint = transform.toImage(detection.keypoint)
            guard let boardPoint = calibration.boardPoint(fromImage: imagePoint) else { return nil }
            return DartCandidate(boardPoint: boardPoint, confidence: Double(detection.score), imagePoint: imagePoint)
        }
    }

    /// Ausschnitt rund ums Board (inkl. Surround und Platz für die Flights). Der Zoom gegenüber dem
    /// Vollbild wird begrenzt, damit die Darts nicht größer erscheinen als im Training.
    nonisolated static func dartRegion(calibration: BoardCalibration, frameSize: CGSize, inputSize: CGFloat, maxZoom: CGFloat) -> CGRect {
        let full = CGRect(origin: .zero, size: frameSize)
        guard maxZoom > 1.01,
              var roi = calibration.imageBounds(boardRadius: BoardGeometry.surroundRadius * 1.2)?.intersection(full),
              !roi.isNull, roi.width > 32, roi.height > 32
        else { return full }

        let fullScale = min(inputSize / frameSize.width, inputSize / frameSize.height)
        let roiScale = min(inputSize / roi.width, inputSize / roi.height)
        let zoom = roiScale / fullScale
        guard zoom > 1.05 else { return full }

        if zoom > maxZoom {
            let grow = zoom / maxZoom
            roi = roi.insetBy(dx: -roi.width * (grow - 1) / 2, dy: -roi.height * (grow - 1) / 2)
            if roi.minX < 0 { roi.origin.x = 0 }
            if roi.minY < 0 { roi.origin.y = 0 }
            if roi.maxX > full.maxX { roi.origin.x = max(0, full.maxX - roi.width) }
            if roi.maxY > full.maxY { roi.origin.y = max(0, full.maxY - roi.height) }
            roi = roi.intersection(full)
        }
        return roi
    }

    // MARK: - CoreML

    private func predict(_ model: MLModel, input: ModelInput, buffer: CVPixelBuffer) throws -> MLMultiArray {
        let features = try MLDictionaryFeatureProvider(dictionary: [input.name: MLFeatureValue(pixelBuffer: buffer)])
        let output = try model.prediction(from: features)
        for name in output.featureNames.sorted() {
            if let array = output.featureValue(for: name)?.multiArrayValue { return array }
        }
        throw DetectionError.invalidModelOutput
    }

    nonisolated private static func modelURL(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "mlmodelc")
    }

    nonisolated private static func imageInput(of model: MLModel) throws -> ModelInput {
        for (name, description) in model.modelDescription.inputDescriptionsByName where description.type == .image {
            let size = description.imageConstraint.map { max($0.pixelsWide, $0.pixelsHigh) } ?? 1216
            return ModelInput(name: name, size: size)
        }
        throw DetectionError.invalidModelOutput
    }
}
