import Foundation
import CoreGraphics

/// Die vier Kalibrierpunkte in Bildkoordinaten (Pixel, Ursprung oben links, aufrechtes Bild).
nonisolated struct BoardKeypoints: Codable, Equatable, Sendable {
    var top: CGPoint
    var right: CGPoint
    var bottom: CGPoint
    var left: CGPoint

    init(top: CGPoint, right: CGPoint, bottom: CGPoint, left: CGPoint) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    init?(points: [CGPoint]) {
        guard points.count == 4 else { return nil }
        self.init(top: points[0], right: points[1], bottom: points[2], left: points[3])
    }

    var points: [CGPoint] { [top, right, bottom, left] }

    func scaled(x sx: CGFloat, y sy: CGFloat) -> BoardKeypoints {
        BoardKeypoints(
            top: CGPoint(x: top.x * sx, y: top.y * sy),
            right: CGPoint(x: right.x * sx, y: right.y * sy),
            bottom: CGPoint(x: bottom.x * sx, y: bottom.y * sy),
            left: CGPoint(x: left.x * sx, y: left.y * sy)
        )
    }

    /// Lineare Mischung zweier Messungen (`weight` = Anteil von `b`).
    static func blend(_ a: BoardKeypoints, _ b: BoardKeypoints, weight: CGFloat) -> BoardKeypoints {
        func mix(_ p: CGPoint, _ q: CGPoint) -> CGPoint {
            CGPoint(x: p.x + (q.x - p.x) * weight, y: p.y + (q.y - p.y) * weight)
        }
        return BoardKeypoints(top: mix(a.top, b.top), right: mix(a.right, b.right),
                              bottom: mix(a.bottom, b.bottom), left: mix(a.left, b.left))
    }

    /// Größter Abstand zwischen korrespondierenden Punkten (Pixel).
    func maxDistance(to other: BoardKeypoints) -> CGFloat {
        zip(points, other.points).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
    }

    /// Median je Koordinate – robust gegen einzelne Fehlerkennungen.
    static func median(of samples: [BoardKeypoints]) -> BoardKeypoints? {
        guard !samples.isEmpty else { return nil }
        func med(_ values: [CGFloat]) -> CGFloat {
            let s = values.sorted()
            let n = s.count
            return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
        }
        var result: [CGPoint] = []
        for i in 0..<4 {
            result.append(CGPoint(
                x: med(samples.map { $0.points[i].x }),
                y: med(samples.map { $0.points[i].y })
            ))
        }
        return BoardKeypoints(points: result)
    }

    /// Mittelwert aller Messungen, die nahe am Median liegen. Mitteln über mehrere Frames
    /// reduziert das Rauschen der Kalibrierpunkte deutlich – und damit systematische Wertungsfehler.
    static func robustAverage(of samples: [BoardKeypoints], tolerance: CGFloat) -> (keypoints: BoardKeypoints, inliers: Int)? {
        guard let med = median(of: samples) else { return nil }
        let inliers = samples.filter { $0.maxDistance(to: med) <= tolerance }
        guard !inliers.isEmpty else { return nil }
        var sums = [CGPoint](repeating: .zero, count: 4)
        for sample in inliers {
            let pts = sample.points
            for i in 0..<4 {
                sums[i].x += pts[i].x
                sums[i].y += pts[i].y
            }
        }
        let n = CGFloat(inliers.count)
        guard let avg = BoardKeypoints(points: sums.map { CGPoint(x: $0.x / n, y: $0.y / n) }) else { return nil }
        return (avg, inliers.count)
    }
}

/// Abbildung zwischen Kamerabild (Pixel) und Board (mm), berechnet aus den 4 Kalibrierpunkten.
nonisolated struct BoardCalibration: Equatable, Sendable {
    let keypoints: BoardKeypoints
    let imageSize: CGSize
    let imageToBoard: Matrix3
    let boardToImage: Matrix3

    init?(keypoints: BoardKeypoints, imageSize: CGSize) {
        guard Self.problem(with: keypoints, imageSize: imageSize) == nil else { return nil }
        guard let h = Homography.estimate(from: keypoints.points, to: BoardGeometry.calibrationPoints),
              let inverse = h.inverse,
              let bullInImage = inverse.apply(.zero),
              Self.convexPolygon(keypoints.points, contains: bullInImage)
        else { return nil }
        self.keypoints = keypoints
        self.imageSize = imageSize
        self.imageToBoard = h
        self.boardToImage = inverse
    }

    /// Prüft, ob die Punkte eine plausible Board-Ansicht ergeben. Gibt eine Fehlermeldung zurück oder `nil`.
    static func problem(with keypoints: BoardKeypoints, imageSize: CGSize) -> String? {
        let pts = keypoints.points
        guard imageSize.width > 0, imageSize.height > 0,
              pts.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
        else { return "Ungültige Kalibrierpunkte" }

        let margin = 0.1 * max(imageSize.width, imageSize.height)
        let allowed = CGRect(origin: .zero, size: imageSize).insetBy(dx: -margin, dy: -margin)
        guard pts.allSatisfy({ allowed.contains($0) }) else {
            return "Das Board ist nicht vollständig im Bild."
        }

        // top → right → bottom → left muss im Bild ein konvexes Viereck im Uhrzeigersinn sein.
        for i in 0..<4 {
            let a = pts[i], b = pts[(i + 1) % 4], c = pts[(i + 2) % 4]
            let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if cross <= 0 { return "Kalibrierpunkte sind vertauscht oder verdeckt." }
        }

        let d1 = hypot(pts[0].x - pts[2].x, pts[0].y - pts[2].y)
        let d2 = hypot(pts[1].x - pts[3].x, pts[1].y - pts[3].y)
        let minSide = min(imageSize.width, imageSize.height)
        if min(d1, d2) < 0.12 * minSide {
            return "Das Board ist zu klein im Bild – näher heran oder zoomen."
        }
        if max(d1, d2) / max(min(d1, d2), 1) > 4 {
            return "Der Blickwinkel ist zu flach – Kamera frontaler ausrichten."
        }
        return nil
    }

    static func convexPolygon(_ polygon: [CGPoint], contains p: CGPoint) -> Bool {
        guard polygon.count >= 3 else { return false }
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
            if cross <= 0 { return false }
        }
        return true
    }

    func boardPoint(fromImage p: CGPoint) -> CGPoint? { imageToBoard.apply(p) }
    func imagePoint(fromBoard p: CGPoint) -> CGPoint? { boardToImage.apply(p) }

    /// Bildausschnitt, der einen Board-Kreis mit gegebenem Radius (mm) umschließt.
    func imageBounds(boardRadius: Double) -> CGRect? {
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for i in 0..<72 {
            let boardPoint = BoardGeometry.point(radius: boardRadius, angleDegrees: Double(i) * 5)
            guard let p = imagePoint(fromBoard: boardPoint) else { continue }
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        guard minX.isFinite, minY.isFinite, maxX > minX, maxY > minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Effektive Auflösung: Bildpixel pro Millimeter entlang des Doppelrings.
    /// Unter ~2 px/mm wird es für Doppel/Triple knapp.
    var pixelsPerMillimeter: Double {
        var perimeter = 0.0
        var previous: CGPoint?
        for i in 0...72 {
            let boardPoint = BoardGeometry.point(radius: BoardGeometry.doubleOuterRadius, angleDegrees: Double(i) * 5)
            guard let p = imagePoint(fromBoard: boardPoint) else { previous = nil; continue }
            if let previous { perimeter += Double(hypot(p.x - previous.x, p.y - previous.y)) }
            previous = p
        }
        return perimeter / (2 * .pi * BoardGeometry.doubleOuterRadius)
    }
}
