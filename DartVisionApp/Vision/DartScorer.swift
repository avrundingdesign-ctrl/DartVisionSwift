import Foundation

// MARK: - Ergebnis eines Dart-Treffers

struct DartScore {
    let value: Int          // Gesamtscore (z.B. 60 für T20)
    let segment: Int        // Sektor-Zahl (1-20, 25, 50)
    let multiplier: Int     // 1=Single, 2=Double/Bull, 3=Triple
    let fieldType: String   // "bull", "outer_bull", "triple", "double", "single", "miss"
}

// MARK: - Score-Berechnung

/// Port von V4_SimulateBoardOnWarpedImageKey.py
/// Berechnet den Score eines Darts auf dem entzerrten 400×400 Board.
struct DartScorer {

    // Board-Geometrie (identisch zu Python)
    static let size: CGFloat = 400.0
    static let R: CGFloat = 200.0
    static let center = CGPoint(x: R, y: R)

    // Radien in Pixeln (SIZE=400, R=200)
    static let innerBullRadius: CGFloat = 7.5
    static let outerBullRadius: CGFloat = 18.7
    static let tripleInner: CGFloat = 116.5
    static let tripleOuter: CGFloat = 125.9
    static let doubleInner: CGFloat = 190.6
    static let doubleOuter: CGFloat = 200.0

    // Sektoren im Uhrzeigersinn, 12 Uhr = 20
    static let sectors = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17,
                           3, 19, 7, 16, 8, 11, 14, 9, 12, 5]

    // Vorberechnete Sektor-Grenzen (start/end Winkel)
    private struct SectorRange {
        let num: Int
        let start: Double  // in Grad
        let end: Double    // in Grad
    }

    private static let sectorRanges: [SectorRange] = {
        sectors.enumerated().map { i, num in
            let start = Double(i * 18 - 9)
            let end = Double((i + 1) * 18 - 9)
            return SectorRange(num: num, start: start, end: end)
        }
    }()

    /// Berechnet Score und Feldart für einen Punkt auf dem entzerrten 400×400 Board.
    /// Port von get_score(x, y, sectors) aus Python.
    static func getScore(at point: CGPoint) -> DartScore {
        let dx = Double(point.x) - Double(R)
        let dy = Double(point.y) - Double(R)
        let r = hypot(dx, dy)  // Abstand vom Mittelpunkt

        // Winkel: 0° = oben (12 Uhr), im Uhrzeigersinn
        let ang = (atan2(dx, -dy) * 180.0 / .pi + 360.0).truncatingRemainder(dividingBy: 360.0)

        // Inner Bull (50)
        if r <= Double(innerBullRadius) {
            return DartScore(value: 50, segment: 50, multiplier: 2, fieldType: "bull")
        }

        // Outer Bull (25)
        if r <= Double(outerBullRadius) {
            return DartScore(value: 25, segment: 25, multiplier: 1, fieldType: "outer_bull")
        }

        // Sektor bestimmen (Winkel → Zahl)
        var field: Int? = nil
        for sector in sectorRanges {
            let start = ((sector.start) + 360.0).truncatingRemainder(dividingBy: 360.0)
            let end = ((sector.end) + 360.0).truncatingRemainder(dividingBy: 360.0)

            let inside: Bool
            if start < end {
                inside = ang >= start && ang < end
            } else {
                // Wraparound (z.B. 351°–9° für Sektor 20)
                inside = ang >= start || ang < end
            }

            if inside {
                field = sector.num
                break
            }
        }

        guard let segment = field else {
            return DartScore(value: 0, segment: 0, multiplier: 0, fieldType: "miss")
        }

        // Ring bestimmen
        if r >= Double(tripleInner) && r <= Double(tripleOuter) {
            return DartScore(value: segment * 3, segment: segment, multiplier: 3, fieldType: "triple")
        }
        if r >= Double(doubleInner) && r <= Double(doubleOuter) {
            return DartScore(value: segment * 2, segment: segment, multiplier: 2, fieldType: "double")
        }
        if r < Double(doubleOuter) {
            return DartScore(value: segment, segment: segment, multiplier: 1, fieldType: "single")
        }

        // Außerhalb des Boards
        return DartScore(value: 0, segment: 0, multiplier: 0, fieldType: "miss")
    }
}
