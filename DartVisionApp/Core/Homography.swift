import Foundation
import CoreGraphics

/// 3×3-Matrix (row-major) für projektive Transformationen.
nonisolated struct Matrix3: Equatable, Sendable {
    var m: [Double]

    init(_ m: [Double]) {
        precondition(m.count == 9, "Matrix3 braucht 9 Werte")
        self.m = m
    }

    static let identity = Matrix3([1, 0, 0, 0, 1, 0, 0, 0, 1])

    static func * (a: Matrix3, b: Matrix3) -> Matrix3 {
        var r = [Double](repeating: 0, count: 9)
        for row in 0..<3 {
            for col in 0..<3 {
                var sum = 0.0
                for k in 0..<3 { sum += a.m[row * 3 + k] * b.m[k * 3 + col] }
                r[row * 3 + col] = sum
            }
        }
        return Matrix3(r)
    }

    var determinant: Double {
        let (a, b, c, d, e, f, g, h, i) = (m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8])
        return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    }

    var inverse: Matrix3? {
        let (a, b, c, d, e, f, g, h, i) = (m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8])
        let det = determinant
        guard abs(det) > 1e-15, det.isFinite else { return nil }
        let inv = [
            (e * i - f * h), -(b * i - c * h), (b * f - c * e),
            -(d * i - f * g), (a * i - c * g), -(a * f - c * d),
            (d * h - e * g), -(a * h - b * g), (a * e - b * d)
        ]
        return Matrix3(inv.map { $0 / det })
    }

    /// Wendet die Matrix auf einen Punkt an (homogene Division). `nil` bei Punkten im Unendlichen.
    func apply(_ p: CGPoint) -> CGPoint? {
        let x = Double(p.x), y = Double(p.y)
        let w = m[6] * x + m[7] * y + m[8]
        guard abs(w) > 1e-12 else { return nil }
        let u = (m[0] * x + m[1] * y + m[2]) / w
        let v = (m[3] * x + m[4] * y + m[5]) / w
        guard u.isFinite, v.isFinite else { return nil }
        return CGPoint(x: u, y: v)
    }
}

nonisolated enum Homography {

    /// Schätzt H mit H · src ≈ dst über eine normalisierte DLT (Hartley).
    /// Bei genau 4 Punkten ist die Lösung exakt, bei mehr Punkten Least Squares.
    static func estimate(from src: [CGPoint], to dst: [CGPoint]) -> Matrix3? {
        guard src.count == dst.count, src.count >= 4 else { return nil }
        guard let srcNorm = normalize(src), let dstNorm = normalize(dst) else { return nil }
        let ts = srcNorm.transform, td = dstNorm.transform
        let srcN = srcNorm.points, dstN = dstNorm.points

        // Normalengleichungen AᵀA·h = Aᵀb mit h33 = 1.
        var ata = [Double](repeating: 0, count: 64)
        var atb = [Double](repeating: 0, count: 8)

        func accumulate(_ row: [Double], _ b: Double) {
            for i in 0..<8 {
                atb[i] += row[i] * b
                for j in 0..<8 { ata[i * 8 + j] += row[i] * row[j] }
            }
        }

        for i in 0..<srcN.count {
            let x = srcN[i].x, y = srcN[i].y
            let u = dstN[i].x, v = dstN[i].y
            accumulate([x, y, 1, 0, 0, 0, -x * u, -y * u], u)
            accumulate([0, 0, 0, x, y, 1, -x * v, -y * v], v)
        }

        guard let h = solveLinearSystem(ata, atb, n: 8) else { return nil }
        let hn = Matrix3([h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], 1])
        guard let tdInverse = td.inverse else { return nil }
        let full = tdInverse * hn * ts
        let scale = full.m[8]
        guard abs(scale) > 1e-12 else { return nil }
        let result = Matrix3(full.m.map { $0 / scale })
        guard result.m.allSatisfy({ $0.isFinite }) else { return nil }
        return result
    }

    nonisolated private struct Normalization {
        let transform: Matrix3
        let points: [(x: Double, y: Double)]
    }

    /// Verschiebt Punkte in den Schwerpunkt und skaliert auf mittleren Abstand √2.
    private static func normalize(_ points: [CGPoint]) -> Normalization? {
        let n = Double(points.count)
        let cx = points.reduce(0.0) { $0 + Double($1.x) } / n
        let cy = points.reduce(0.0) { $0 + Double($1.y) } / n
        let meanDist = points.reduce(0.0) { $0 + hypot(Double($1.x) - cx, Double($1.y) - cy) } / n
        guard meanDist > 1e-9 else { return nil }
        let s = 2.0.squareRoot() / meanDist
        let t = Matrix3([s, 0, -s * cx, 0, s, -s * cy, 0, 0, 1])
        let normalized = points.map { (x: (Double($0.x) - cx) * s, y: (Double($0.y) - cy) * s) }
        return Normalization(transform: t, points: normalized)
    }

    /// Gauß-Elimination mit Spaltenpivotisierung für ein n×n-System (row-major).
    static func solveLinearSystem(_ matrix: [Double], _ rhs: [Double], n: Int) -> [Double]? {
        var a = matrix
        var b = rhs
        for col in 0..<n {
            var pivot = col
            var best = abs(a[col * n + col])
            for row in (col + 1)..<n where abs(a[row * n + col]) > best {
                best = abs(a[row * n + col])
                pivot = row
            }
            guard best > 1e-12 else { return nil }
            if pivot != col {
                for k in 0..<n { a.swapAt(col * n + k, pivot * n + k) }
                b.swapAt(col, pivot)
            }
            for row in (col + 1)..<n {
                let factor = a[row * n + col] / a[col * n + col]
                if factor == 0 { continue }
                for k in col..<n { a[row * n + k] -= factor * a[col * n + k] }
                b[row] -= factor * b[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for k in (row + 1)..<n { sum -= a[row * n + k] * x[k] }
            x[row] = sum / a[row * n + row]
        }
        return x
    }
}
