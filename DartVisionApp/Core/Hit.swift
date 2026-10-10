import Foundation

/// Ring eines Treffers auf dem Dartboard.
nonisolated enum Ring: String, Codable, Hashable, Sendable {
    case miss
    case single
    case double
    case triple
    case outerBull
    case bull
}

/// Ein einzelner Treffer (Segment + Ring). Unabhängig davon, ob er von der Kamera
/// oder manuell erfasst wurde.
nonisolated struct Hit: Hashable, Codable, Sendable {
    let ring: Ring
    /// 1...20 für Zahlenfelder, 25 für Bull-Ringe, 0 für Miss.
    let number: Int

    static let miss = Hit(ring: .miss, number: 0)
    static let outerBull = Hit(ring: .outerBull, number: 25)
    static let bull = Hit(ring: .bull, number: 25)
    static func single(_ n: Int) -> Hit { Hit(ring: .single, number: n) }
    static func double(_ n: Int) -> Hit { Hit(ring: .double, number: n) }
    static func triple(_ n: Int) -> Hit { Hit(ring: .triple, number: n) }

    var multiplier: Int {
        switch ring {
        case .miss: return 0
        case .single, .outerBull: return 1
        case .double, .bull: return 2
        case .triple: return 3
        }
    }

    var points: Int {
        switch ring {
        case .miss: return 0
        case .outerBull: return 25
        case .bull: return 50
        case .single, .double, .triple: return number * multiplier
        }
    }

    /// Zählt als Doppel (Double-Out / Double-In). Das Bull (50) ist ein Doppel.
    var isDouble: Bool { ring == .double || ring == .bull }
    var isTriple: Bool { ring == .triple }

    /// Kurzschreibweise für Anzeige: "T20", "D16", "5", "25", "Bull", "Miss".
    var label: String {
        switch ring {
        case .miss: return "Miss"
        case .single: return "\(number)"
        case .double: return "D\(number)"
        case .triple: return "T\(number)"
        case .outerBull: return "25"
        case .bull: return "Bull"
        }
    }

    /// Text für die Sprachausgabe.
    var spokenText: String {
        switch ring {
        case .miss: return "Daneben"
        case .single: return "\(number)"
        case .double: return "Doppel \(number)"
        case .triple: return "Triple \(number)"
        case .outerBull: return "25"
        case .bull: return "Bull"
        }
    }

    /// Alle Treffer mit Punkten (S1–S20, D1–D20, T1–T20, 25, Bull).
    static let allScoring: [Hit] = {
        var hits: [Hit] = []
        for n in 1...20 {
            hits.append(.single(n))
            hits.append(.double(n))
            hits.append(.triple(n))
        }
        hits.append(.outerBull)
        hits.append(.bull)
        return hits
    }()
}
