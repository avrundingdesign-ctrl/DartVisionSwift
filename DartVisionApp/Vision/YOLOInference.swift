import CoreML
import Vision
import UIKit

// MARK: - Erkannte Board-Keypoints

struct DetectedKeypoint {
    let label: String      // "TOP", "Right", "Bottom", "Left"
    let point: CGPoint     // Pixel-Koordinaten im Originalbild
    let confidence: Float
}

// MARK: - Erkannter Dart

struct DetectedDart {
    let center: CGPoint    // Keypoint (Dart-Spitze) in Pixel-Koordinaten
    let confidence: Float
}

// MARK: - YOLO CoreML Inferenz

/// Führt YOLO-Pose-Inferenz auf dem iPhone aus.
/// Ersetzt den Server-Call + V4_YOLODartKoordinates.py
class YOLOInference {

    // CoreML-Modelle
    private let boardModel: MLModel
    private let dartsModel: MLModel

    // Modell-Input-Größe
    static let inputSize: CGFloat = 1216

    // Klassennamen
    private let boardClasses = ["TOP", "Right", "Bottom", "Left"]

    // NMS-Parameter
    private let confidenceThreshold: Float = 0.25
    private let iouThreshold: Float = 0.45

    // MARK: - Init

    init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        guard let boardURL = Bundle.main.url(forResource: "Board", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "Board", withExtension: "mlpackage"),
              let dartsURL = Bundle.main.url(forResource: "Darts", withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: "Darts", withExtension: "mlpackage")
        else {
            throw YOLOError.modelNotFound
        }

        boardModel = try MLModel(contentsOf: boardURL, configuration: config)
        dartsModel = try MLModel(contentsOf: dartsURL, configuration: config)
    }

    // MARK: - Board-Keypoints erkennen

    /// Erkennt die 4 Board-Keypoints (TOP, Right, Bottom, Left).
    /// Ersetzt run_yolo_on_image() aus V4_YOLODartKoordinates.py
    func detectBoardKeypoints(in image: CGImage) throws -> [DetectedKeypoint] {
        let pixelBuffer = try resizeToPixelBuffer(image: image, size: Int(Self.inputSize))
        let input = try MLDictionaryFeatureProvider(
            dictionary: ["image": MLFeatureValue(pixelBuffer: pixelBuffer)]
        )
        let output = try boardModel.prediction(from: input)

        guard let multiArray = output.featureValue(for: "var_1344")?.multiArrayValue else {
            throw YOLOError.invalidOutput
        }

        // Board: (1, 11, 30324) → 4 bbox + 4 class probs + 3 keypoint (x,y,conf)
        let numClasses = 4
        let numAnchors = 30324
        let rawDetections = parseRawOutput(
            multiArray: multiArray,
            numClasses: numClasses,
            numAnchors: numAnchors,
            numKeypoints: 1
        )

        // NMS anwenden
        let filtered = nonMaxSuppression(
            detections: rawDetections,
            iouThreshold: iouThreshold
        )

        // In DetectedKeypoint umwandeln, skaliert auf Originalbild
        let scaleX = CGFloat(image.width) / Self.inputSize
        let scaleY = CGFloat(image.height) / Self.inputSize

        var keypoints: [DetectedKeypoint] = []
        // Pro Klasse nur die beste Detection nehmen (wie sort_by_class in Python)
        var bestPerClass: [Int: RawDetection] = [:]

        for det in filtered {
            if bestPerClass[det.classIndex] == nil || det.confidence > bestPerClass[det.classIndex]!.confidence {
                bestPerClass[det.classIndex] = det
            }
        }

        for (classIdx, det) in bestPerClass {
            guard classIdx < boardClasses.count, let kp = det.keypoints.first else { continue }
            keypoints.append(DetectedKeypoint(
                label: boardClasses[classIdx],
                point: CGPoint(x: kp.x * scaleX, y: kp.y * scaleY),
                confidence: det.confidence
            ))
        }

        return keypoints
    }

    // MARK: - Darts erkennen

    /// Erkennt Dart-Positionen (Spitzen).
    /// Ersetzt run_yolo_on_image2() aus V4_YOLODartKoordinates.py
    func detectDarts(in image: CGImage) throws -> [DetectedDart] {
        let pixelBuffer = try resizeToPixelBuffer(image: image, size: Int(Self.inputSize))
        let input = try MLDictionaryFeatureProvider(
            dictionary: ["image": MLFeatureValue(pixelBuffer: pixelBuffer)]
        )
        let output = try dartsModel.prediction(from: input)

        guard let multiArray = output.featureValue(for: "var_1344")?.multiArrayValue else {
            throw YOLOError.invalidOutput
        }

        // Darts: (1, 8, 30324) → 4 bbox + 1 class prob + 3 keypoint (x,y,conf)
        let numClasses = 1
        let numAnchors = 30324
        let rawDetections = parseRawOutput(
            multiArray: multiArray,
            numClasses: numClasses,
            numAnchors: numAnchors,
            numKeypoints: 1
        )

        // NMS anwenden
        let filtered = nonMaxSuppression(
            detections: rawDetections,
            iouThreshold: iouThreshold
        )

        // In DetectedDart umwandeln, skaliert auf Originalbild
        let scaleX = CGFloat(image.width) / Self.inputSize
        let scaleY = CGFloat(image.height) / Self.inputSize

        return filtered.map { det in
            let kp = det.keypoints.first ?? CGPoint(x: det.cx, y: det.cy)
            return DetectedDart(
                center: CGPoint(x: kp.x * scaleX, y: kp.y * scaleY),
                confidence: det.confidence
            )
        }
    }

    // MARK: - Raw Output Parsing

    private struct RawDetection {
        let cx: CGFloat
        let cy: CGFloat
        let width: CGFloat
        let height: CGFloat
        let classIndex: Int
        let confidence: Float
        let keypoints: [CGPoint]  // Keypoint-Positionen
    }

    /// Parst den rohen YOLO-Output-Tensor.
    /// Format: (1, channels, numAnchors) wobei channels = 4 + numClasses + numKeypoints*3
    private func parseRawOutput(
        multiArray: MLMultiArray,
        numClasses: Int,
        numAnchors: Int,
        numKeypoints: Int
    ) -> [RawDetection] {

        let channels = 4 + numClasses + numKeypoints * 3
        let pointer = multiArray.dataPointer.bindMemory(to: Float.self, capacity: channels * numAnchors)

        // Hilfsfunktion: Wert an Position [channel, anchor] lesen
        // Layout: (1, channels, numAnchors) → offset = channel * numAnchors + anchor
        func value(channel: Int, anchor: Int) -> Float {
            pointer[channel * numAnchors + anchor]
        }

        var detections: [RawDetection] = []

        for a in 0..<numAnchors {
            // Beste Klasse finden
            var bestClassIdx = 0
            var bestClassProb: Float = 0

            for c in 0..<numClasses {
                let prob = value(channel: 4 + c, anchor: a)
                if prob > bestClassProb {
                    bestClassProb = prob
                    bestClassIdx = c
                }
            }

            // Confidence-Filter
            guard bestClassProb >= confidenceThreshold else { continue }

            // Bounding Box (center format)
            let cx = CGFloat(value(channel: 0, anchor: a))
            let cy = CGFloat(value(channel: 1, anchor: a))
            let w  = CGFloat(value(channel: 2, anchor: a))
            let h  = CGFloat(value(channel: 3, anchor: a))

            // Keypoints
            var kps: [CGPoint] = []
            for k in 0..<numKeypoints {
                let kpOffset = 4 + numClasses + k * 3
                let kpX = CGFloat(value(channel: kpOffset, anchor: a))
                let kpY = CGFloat(value(channel: kpOffset + 1, anchor: a))
                // kpConf = value(channel: kpOffset + 2, anchor: a)  // nicht verwendet
                kps.append(CGPoint(x: kpX, y: kpY))
            }

            detections.append(RawDetection(
                cx: cx, cy: cy, width: w, height: h,
                classIndex: bestClassIdx,
                confidence: bestClassProb,
                keypoints: kps
            ))
        }

        return detections
    }

    // MARK: - Non-Maximum Suppression

    private func nonMaxSuppression(
        detections: [RawDetection],
        iouThreshold: Float
    ) -> [RawDetection] {

        // Nach Confidence sortieren (höchste zuerst)
        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var kept: [RawDetection] = []

        for det in sorted {
            // Prüfe ob diese Detection mit einer bereits behaltenen überlappt
            var dominated = false
            for existing in kept {
                if iou(det, existing) > iouThreshold {
                    dominated = true
                    break
                }
            }
            if !dominated {
                kept.append(det)
            }
        }

        return kept
    }

    /// Intersection over Union für zwei Bounding Boxes (center format)
    private func iou(_ a: RawDetection, _ b: RawDetection) -> Float {
        let ax1 = a.cx - a.width / 2, ay1 = a.cy - a.height / 2
        let ax2 = a.cx + a.width / 2, ay2 = a.cy + a.height / 2
        let bx1 = b.cx - b.width / 2, by1 = b.cy - b.height / 2
        let bx2 = b.cx + b.width / 2, by2 = b.cy + b.height / 2

        let ix1 = max(ax1, bx1), iy1 = max(ay1, by1)
        let ix2 = min(ax2, bx2), iy2 = min(ay2, by2)

        let interW = max(0, ix2 - ix1)
        let interH = max(0, iy2 - iy1)
        let interArea = interW * interH

        let areaA = a.width * a.height
        let areaB = b.width * b.height
        let unionArea = areaA + areaB - interArea

        guard unionArea > 0 else { return 0 }
        return Float(interArea / unionArea)
    }

    // MARK: - Bild → CVPixelBuffer

    /// Skaliert ein CGImage auf die Modell-Input-Größe und erstellt einen CVPixelBuffer.
    private func resizeToPixelBuffer(image: CGImage, size: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, size, size,
            kCVPixelFormatType_32BGRA, attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw YOLOError.pixelBufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: size, height: size,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw YOLOError.pixelBufferCreationFailed
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        return buffer
    }
}

// MARK: - Errors

enum YOLOError: Error, LocalizedError {
    case modelNotFound
    case invalidOutput
    case pixelBufferCreationFailed

    var errorDescription: String? {
        switch self {
        case .modelNotFound: return "CoreML-Modell nicht gefunden"
        case .invalidOutput: return "Ungültiges Modell-Output"
        case .pixelBufferCreationFailed: return "PixelBuffer konnte nicht erstellt werden"
        }
    }
}
