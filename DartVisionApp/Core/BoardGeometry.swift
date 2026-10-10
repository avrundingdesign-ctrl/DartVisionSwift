import Foundation
import CoreGraphics

/// Maße eines Standard-Steeldartboards in Millimetern.
///
/// Board-Koordinatensystem: Ursprung im Bull, x nach rechts, y nach oben, Einheit mm.
/// Winkel werden im Uhrzeigersinn ab 12 Uhr gemessen (die 20 liegt bei 0°).
nonisolated enum BoardGeometry {
    static let innerBullRadius: Double = 6.35
    static let outerBullRadius: Double = 15.9
    static let trebleInnerRadius: Double = 99.0
    static let trebleOuterRadius: Double = 107.0
    static let doubleInnerRadius: Double = 162.0
    static let doubleOuterRadius: Double = 170.0
    /// Bis zu diesem Radius zählt ein erkannter Dart als "steckt im Surround" (0 Punkte).
    /// Erkennungen weiter außen werden als Fehlerkennung verworfen.
    static let surroundRadius: Double = 225.0

    /// Zahlen im Uhrzeigersinn, beginnend oben.
    static let numbers: [Int] = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

    static let ringRadii: [Double] = [
        innerBullRadius, outerBullRadius, trebleInnerRadius,
        trebleOuterRadius, doubleInnerRadius, doubleOuterRadius
    ]

    /// Kalibrierpunkte (DeepDarts-Konvention, wie das YOLO-Board-Modell):
    /// Außenkante des Doppelrings an den Segmentgrenzen 5/20, 13/6, 17/3 und 8/11.
    /// Reihenfolge: top, right, bottom, left.
    static let calibrationAngles: [Double] = [351, 81, 171, 261]

    static var calibrationPoints: [CGPoint] {
        calibrationAngles.map { point(radius: doubleOuterRadius, angleDegrees: $0) }
    }

    // MARK: - Polar <-> kartesisch

    /// Winkel im Uhrzeigersinn ab 12 Uhr in Grad, Bereich [0, 360).
    static func angleDegrees(of p: CGPoint) -> Double {
        let a = atan2(Double(p.x), Double(p.y)) * 180 / .pi
        return a < 0 ? a + 360 : a
    }

    static func radius(of p: CGPoint) -> Double {
        hypot(Double(p.x), Double(p.y))
    }

    static func point(radius: Double, angleDegrees deg: Double) -> CGPoint {
        let rad = deg * .pi / 180
        return CGPoint(x: radius * sin(rad), y: radius * cos(rad))
    }

    /// Mittelwinkel eines Zahlensegments.
    static func centerAngle(of number: Int) -> Double? {
        guard let index = numbers.firstIndex(of: number) else { return nil }
        return Double(index) * 18
    }

    static func number(atAngle deg: Double) -> Int {
        var shifted = (deg + 9).truncatingRemainder(dividingBy: 360)
        if shifted < 0 { shifted += 360 }
        let index = Int(shifted / 18) % 20
        return numbers[index]
    }

    // MARK: - Scoring

    static func hit(at p: CGPoint) -> Hit {
        let r = radius(of: p)
        if r <= innerBullRadius { return .bull }
        if r <= outerBullRadius { return .outerBull }
        if r > doubleOuterRadius { return .miss }
        let n = number(atAngle: angleDegrees(of: p))
        if r >= trebleInnerRadius && r <= trebleOuterRadius { return .triple(n) }
        if r >= doubleInnerRadius { return .double(n) }
        return .single(n)
    }

    /// Abstand in mm zum nächstgelegenen Draht (Ring oder Segmentgrenze).
    /// Kleine Werte bedeuten: die Wertung kippt schon bei minimalem Erkennungsfehler.
    static func wireDistance(at p: CGPoint) -> Double {
        let r = radius(of: p)
        var best = ringRadii.map { abs(r - $0) }.min() ?? .infinity
        if r > outerBullRadius {
            let offset = (angleDegrees(of: p) + 9).truncatingRemainder(dividingBy: 18)
            let toWire = min(offset, 18 - offset) * .pi / 180
            best = min(best, r * sin(toWire))
        }
        return best
    }

    /// Repräsentativer Punkt (mm) für einen Treffer – z. B. für manuell eingetragene Darts.
    static func representativePoint(for hit: Hit) -> CGPoint? {
        switch hit.ring {
        case .miss: return nil
        case .bull: return .zero
        case .outerBull: return point(radius: (innerBullRadius + outerBullRadius) / 2, angleDegrees: 45)
        case .triple:
            guard let a = centerAngle(of: hit.number) else { return nil }
            return point(radius: (trebleInnerRadius + trebleOuterRadius) / 2, angleDegrees: a)
        case .double:
            guard let a = centerAngle(of: hit.number) else { return nil }
            return point(radius: (doubleInnerRadius + doubleOuterRadius) / 2, angleDegrees: a)
        case .single:
            guard let a = centerAngle(of: hit.number) else { return nil }
            return point(radius: (trebleOuterRadius + doubleInnerRadius) / 2, angleDegrees: a)
        }
    }
}
