import Foundation
import CoreML
import CoreGraphics

/// Eine Rohdetektion eines Ultralytics-Pose-Modells (Koordinaten im Modell-Input, Pixel).
nonisolated struct PoseDetection: Sendable {
    var box: CGRect
    var classIndex: Int
    var score: Float
    var keypoint: CGPoint
    var keypointConfidence: Float
}

/// Decodiert den Ausgabe-Tensor von YOLO11/YOLOv8-Pose (Export ohne NMS):
/// Form [1, 4 + Klassen + 3, Anker] – Box (cx, cy, w, h), Klassen-Scores, Keypoint (x, y, Sichtbarkeit).
nonisolated enum YOLOPoseDecoder {

    static func decode(_ array: MLMultiArray, numClasses: Int, minScore: Float, maxCandidates: Int = 300) throws -> [PoseDetection] {
        let shape = array.shape.map { $0.intValue }
        let strides = array.strides.map { $0.intValue }
        guard shape.count >= 2 else { throw DetectionError.invalidModelOutput }

        let dims = Array(shape.suffix(2))
        let dimStrides = Array(strides.suffix(2))
        let minChannels = 4 + numClasses + 2

        // Kanäle zuerst ([C, N]) oder zuletzt ([N, C])? Die Ankerzahl ist immer deutlich größer.
        let channelsFirst = dims[0] < dims[1]
        let channels = channelsFirst ? dims[0] : dims[1]
        let anchors = channelsFirst ? dims[1] : dims[0]
        let channelStride = channelsFirst ? dimStrides[0] : dimStrides[1]
        let anchorStride = channelsFirst ? dimStrides[1] : dimStrides[0]
        guard channels >= minChannels else { throw DetectionError.invalidModelOutput }

        let keypointOffset = 4 + numClasses
        let hasVisibility = channels >= keypointOffset + 3

        func run(_ value: (Int) -> Float) -> [PoseDetection] {
            var detections: [PoseDetection] = []
            for anchor in 0..<anchors {
                let base = anchor * anchorStride
                var bestScore: Float = 0
                var bestClass = 0
                for c in 0..<numClasses {
                    let score = value(base + (4 + c) * channelStride)
                    if score > bestScore {
                        bestScore = score
                        bestClass = c
                    }
                }
                guard bestScore >= minScore else { continue }

                let cx = value(base)
                let cy = value(base + channelStride)
                let w = value(base + 2 * channelStride)
                let h = value(base + 3 * channelStride)
                let kx = value(base + keypointOffset * channelStride)
                let ky = value(base + (keypointOffset + 1) * channelStride)
                let visibility = hasVisibility ? value(base + (keypointOffset + 2) * channelStride) : 1

                detections.append(PoseDetection(
                    box: CGRect(x: CGFloat(cx - w / 2), y: CGFloat(cy - h / 2), width: CGFloat(w), height: CGFloat(h)),
                    classIndex: bestClass,
                    score: bestScore,
                    keypoint: CGPoint(x: CGFloat(kx), y: CGFloat(ky)),
                    keypointConfidence: visibility
                ))
            }
            detections.sort { $0.score > $1.score }
            if detections.count > maxCandidates {
                detections.removeSubrange(maxCandidates..<detections.count)
            }
            return detections
        }

        switch array.dataType {
        case .float32:
            return array.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: Float.self)
                return run { p[$0] }
            }
        case .float16:
            return array.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: UInt16.self)
                return run { halfToFloat(p[$0]) }
            }
        case .double:
            return array.withUnsafeBytes { raw in
                let p = raw.bindMemory(to: Double.self)
                return run { Float(p[$0]) }
            }
        default:
            throw DetectionError.invalidModelOutput
        }
    }

    /// Unterdrückt Mehrfacherkennungen desselben Darts. Entscheidend ist der Abstand der Spitzen –
    /// eng gruppierte Darts (z. B. drei im T20) haben stark überlappende Boxen, aber getrennte Spitzen.
    static func suppressDuplicates(_ detections: [PoseDetection], keypointDistance: CGFloat, iouThreshold: CGFloat) -> [PoseDetection] {
        var kept: [PoseDetection] = []
        for detection in detections.sorted(by: { $0.score > $1.score }) {
            let duplicate = kept.contains { other in
                let distance = hypot(other.keypoint.x - detection.keypoint.x, other.keypoint.y - detection.keypoint.y)
                if distance < keypointDistance { return true }
                return iou(other.box, detection.box) > iouThreshold && distance < keypointDistance * 3
            }
            if !duplicate { kept.append(detection) }
        }
        return kept
    }

    /// Beste Detektion je Klasse (für die vier Board-Kalibrierpunkte).
    static func bestPerClass(_ detections: [PoseDetection], numClasses: Int) -> [PoseDetection?] {
        var best = [PoseDetection?](repeating: nil, count: numClasses)
        for detection in detections where detection.classIndex < numClasses {
            if let current = best[detection.classIndex], current.score >= detection.score { continue }
            best[detection.classIndex] = detection
        }
        return best
    }

    /// IEEE-754 half → Float (ohne den Typ `Float16`, der im Intel-Simulator fehlt).
    static func halfToFloat(_ bits: UInt16) -> Float {
        let sign: FloatingPointSign = (bits & 0x8000) != 0 ? .minus : .plus
        let exponent = Int((bits >> 10) & 0x1F)
        let fraction = Float(bits & 0x03FF)
        switch exponent {
        case 0:
            return Float(sign: sign, exponent: -14, significand: fraction / 1024)
        case 31:
            return fraction == 0 ? (sign == .minus ? -.infinity : .infinity) : .nan
        default:
            return Float(sign: sign, exponent: exponent - 15, significand: 1 + fraction / 1024)
        }
    }

    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let inter = intersection.width * intersection.height
        let union = a.width * a.height + b.width * b.height - inter
        return union > 0 ? inter / union : 0
    }
}
