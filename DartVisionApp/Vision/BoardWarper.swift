import Foundation
import Accelerate

// MARK: - Homographie & Koordinaten-Transformation

/// Port von V4_Warp_Image_keypoints.py + V4_Extract_DartCenters.py
/// Berechnet die Homographie aus 4 Board-Keypoints und transformiert Dart-Koordinaten
/// ins normierte 400×400 Board.
struct BoardWarper {

    static let size: CGFloat = 400.0
    static let center = CGPoint(x: 200, y: 200)

    /// Winkelkorrektur (ANGLE_CORRECTION aus Python)
    static let angleCorrection: Double = 9.0

    /// Extra-Rotation aus transform_dart_keypoints_absolute
    static let extraRotation: Double = 9.0

    /// FLIP_X aus Python (standardmäßig false)
    static let flipX: Bool = false

    // MARK: - Zielpunkte

    /// Die 4 Zielpunkte im entzerrten Board (vor Rotation)
    /// Entspricht dst_pts in V4_Warp_Image_keypoints.py
    private static let targetPoints: [CGPoint] = [
        CGPoint(x: 200, y: 0),     // top
        CGPoint(x: 400, y: 200),   // right
        CGPoint(x: 200, y: 400),   // bottom
        CGPoint(x: 0,   y: 200)    // left
    ]

    /// Rotationsmatrix M (2×3) für ANGLE_CORRECTION
    /// Entspricht cv2.getRotationMatrix2D((200, 200), 9, 1.0)
    private static let rotationMatrix: (a: Double, b: Double, tx: Double, ty: Double) = {
        let rad = angleCorrection * .pi / 180.0
        let cosA = cos(rad)
        let sinA = sin(rad)
        let cx = 200.0, cy = 200.0
        // M = [[cos, sin, (1-cos)*cx - sin*cy],
        //      [-sin, cos, sin*cx + (1-cos)*cy]]
        let tx = (1 - cosA) * cx - sinA * cy
        let ty = sinA * cx + (1 - cosA) * cy
        return (cosA, sinA, tx, ty)
    }()

    /// Rotierte Zielpunkte (dst_rot aus Python)
    private static let rotatedTargetPoints: [CGPoint] = {
        let m = rotationMatrix
        return targetPoints.map { p in
            let x = m.a * Double(p.x) + m.b * Double(p.y) + m.tx
            let y = -m.b * Double(p.x) + m.a * Double(p.y) + m.ty
            return CGPoint(x: x, y: y)
        }
    }()

    // MARK: - Homographie berechnen

    /// Berechnet die 3×3 Homographie-Matrix aus 4 Board-Keypoints.
    /// Entspricht cv2.findHomography(src_pts, dst_rot)
    /// Reihenfolge der Keypoints: [top, right, bottom, left]
    static func computeHomography(from keypoints: [DetectedKeypoint]) -> [Double]? {
        // Keypoints in richtige Reihenfolge bringen
        let order = ["TOP", "Right", "Bottom", "Left"]
        var sourcePoints: [CGPoint] = []

        for label in order {
            guard let kp = keypoints.first(where: { $0.label == label }) else {
                return nil  // Nicht alle 4 Keypoints vorhanden
            }
            sourcePoints.append(kp.point)
        }

        return computeHomography(source: sourcePoints, destination: Array(rotatedTargetPoints))
    }

    /// 4-Punkt Homographie über DLT (Direct Linear Transform).
    /// Ersetzt cv2.findHomography() für genau 4 Punktpaare.
    /// Gibt eine 3×3 Matrix als flaches [Double] Array zurück (row-major).
    static func computeHomography(source: [CGPoint], destination: [CGPoint]) -> [Double]? {
        guard source.count >= 4, destination.count >= 4 else { return nil }

        // DLT: Für jedes Punktpaar 2 Gleichungen aufstellen
        // A * h = 0, wobei h die 9 Elemente der Homographie-Matrix sind
        let n = min(source.count, destination.count)
        var A = [Double](repeating: 0, count: 2 * n * 9)

        for i in 0..<n {
            let sx = Double(source[i].x)
            let sy = Double(source[i].y)
            let dx = Double(destination[i].x)
            let dy = Double(destination[i].y)

            // Zeile 2*i:   [-sx, -sy, -1,  0,   0,   0,  dx*sx, dx*sy, dx]
            let row1 = 2 * i
            A[row1 * 9 + 0] = -sx
            A[row1 * 9 + 1] = -sy
            A[row1 * 9 + 2] = -1
            A[row1 * 9 + 3] = 0
            A[row1 * 9 + 4] = 0
            A[row1 * 9 + 5] = 0
            A[row1 * 9 + 6] = dx * sx
            A[row1 * 9 + 7] = dx * sy
            A[row1 * 9 + 8] = dx

            // Zeile 2*i+1: [ 0,   0,   0, -sx, -sy,  -1,  dy*sx, dy*sy, dy]
            let row2 = 2 * i + 1
            A[row2 * 9 + 0] = 0
            A[row2 * 9 + 1] = 0
            A[row2 * 9 + 2] = 0
            A[row2 * 9 + 3] = -sx
            A[row2 * 9 + 4] = -sy
            A[row2 * 9 + 5] = -1
            A[row2 * 9 + 6] = dy * sx
            A[row2 * 9 + 7] = dy * sy
            A[row2 * 9 + 8] = dy
        }

        // SVD lösen: A = U * S * Vt, Lösung ist letzte Zeile von Vt
        let m = 2 * n  // Zeilen
        let nn = 9      // Spalten

        var sValues = [Double](repeating: 0, count: nn)
        var u = [Double](repeating: 0, count: m * m)
        var vt = [Double](repeating: 0, count: nn * nn)
        var work = [Double](repeating: 0, count: max(1, 3 * min(m, nn) + max(m, nn)))
        var lwork = Int32(work.count)
        var info: Int32 = 0
        var mI = Int32(m)
        var nI = Int32(nn)
        var lda = Int32(nn)
        var ldu = Int32(m)
        var ldvt = Int32(nn)
        var jobu: Int8 = Int8(UnicodeScalar("A").value)
        var jobvt: Int8 = Int8(UnicodeScalar("A").value)

        // LAPACK braucht Column-Major, also transponieren wir A
        var At = [Double](repeating: 0, count: m * nn)
        for r in 0..<m {
            for c in 0..<nn {
                At[c * m + r] = A[r * nn + c]
            }
        }

        dgesvd_(&jobu, &jobvt, &mI, &nI, &At, &mI, &sValues, &u, &ldu, &vt, &ldvt, &work, &lwork, &info)

        guard info == 0 else { return nil }

        // Lösung: letzte Zeile von Vt (Index 8)
        var h = [Double](repeating: 0, count: 9)
        for i in 0..<9 {
            h[i] = vt[8 * nn + i]
        }

        // Normalisieren so dass h[8] = 1
        if abs(h[8]) > 1e-10 {
            for i in 0..<9 {
                h[i] /= h[8]
            }
        }

        return h
    }

    // MARK: - Punkt-Transformation

    /// Transformiert einen Dart-Punkt aus dem Originalbild ins normierte 400×400 Board.
    /// Entspricht transform_dart_keypoints_absolute() aus V4_Extract_DartCenters.py
    ///
    /// Schritte:
    /// 1. Homographie anwenden
    /// 2. Optional Flip X
    /// 3. Rotationsmatrix M anwenden
    /// 4. Extra-Rotation
    static func transformPoint(_ point: CGPoint, homography H: [Double]) -> CGPoint {
        // Schritt 1: Homographie anwenden (perspectiveTransform)
        let sx = Double(point.x)
        let sy = Double(point.y)

        let w = H[6] * sx + H[7] * sy + H[8]
        guard abs(w) > 1e-10 else { return .zero }

        var px = (H[0] * sx + H[1] * sy + H[2]) / w
        var py = (H[3] * sx + H[4] * sy + H[5]) / w

        // Schritt 2: Flip X (FLIP_X = false in Python, aber sicherheitshalber)
        if flipX {
            px = Double(size - 1) - px
        }

        // Schritt 3: Rotationsmatrix M anwenden
        let m = rotationMatrix
        let ax = m.a * px + m.b * py + m.tx
        let ay = -m.b * px + m.a * py + m.ty

        // Schritt 4: Extra-Rotation um extraRotation Grad
        let cx = Double(size) / 2.0
        let cy = Double(size) / 2.0
        let dx = ax - cx
        let dy = ay - cy
        let rad = extraRotation * .pi / 180.0
        let rotX = dx * cos(rad) - dy * sin(rad)
        let rotY = dx * sin(rad) + dy * cos(rad)

        let finalX = cx + rotX
        let finalY = cy + rotY

        return CGPoint(x: finalX, y: finalY)
    }

    /// Transformiert mehrere Dart-Punkte auf einmal.
    static func transformDarts(_ darts: [DetectedDart], homography H: [Double]) -> [(position: CGPoint, confidence: Float)] {
        return darts.map { dart in
            let transformed = transformPoint(dart.center, homography: H)
            return (position: transformed, confidence: dart.confidence)
        }
    }
}
