import Foundation

/// Berechnet Finish-Wege für beliebige Reste – statt einer festen Tabelle.
/// Bevorzugt wenige Darts, gängige Doppel (D20/D16/D8 …) und einfache Setup-Würfe.
nonisolated enum CheckoutCalculator {

    /// Bester Finish-Weg mit höchstens `dartsLeft` Darts, oder `nil`, wenn der Rest nicht checkbar ist.
    static func route(for remaining: Int, dartsLeft: Int = 3, outRule: OutRule) -> [Hit]? {
        guard remaining > 0, (1...3).contains(dartsLeft), remaining < maxScore + 1 else { return nil }
        let table: [[[Hit]?]]
        switch outRule {
        case .straight: table = straightTable
        case .double: table = doubleTable
        case .master: table = masterTable
        }
        return table[dartsLeft - 1][remaining]
    }

    static func formatted(_ route: [Hit]) -> String {
        route.map(\.label).joined(separator: " · ")
    }

    // MARK: - Tabellen (einmalig berechnet)

    private static let maxScore = 180

    private static let straightTable = buildTable(for: .straight)
    private static let doubleTable = buildTable(for: .double)
    private static let masterTable = buildTable(for: .master)

    /// table[dartsLeft - 1][rest] → beste Route.
    private static func buildTable(for rule: OutRule) -> [[[Hit]?]] {
        let finishers = Hit.allScoring.filter { rule.allowsFinish(with: $0) }
        let setups = Hit.allScoring

        // best[n][rest] = beste Route mit genau n Darts
        var best = Array(repeating: Array(repeating: (cost: Double.infinity, route: [Hit]()), count: maxScore + 1), count: 3)

        func consider(_ route: [Hit]) {
            let total = route.reduce(0) { $0 + $1.points }
            guard total <= maxScore else { return }
            let c = cost(of: route, rule: rule)
            let n = route.count - 1
            if c < best[n][total].cost { best[n][total] = (c, route) }
        }

        for f in finishers { consider([f]) }
        for s in setups { for f in finishers { consider([s, f]) } }
        // Setup-Darts absteigend (T20 vor T19) – so lesen sich Wege wie im Checkout-Chart.
        for s1 in setups {
            for s2 in setups where s2.points <= s1.points {
                for f in finishers { consider([s1, s2, f]) }
            }
        }

        var table: [[[Hit]?]] = []
        for dartsLeft in 1...3 {
            var row: [[Hit]?] = Array(repeating: nil, count: maxScore + 1)
            for rest in 1...maxScore {
                var choice: (cost: Double, route: [Hit])?
                for n in 0..<dartsLeft where best[n][rest].cost.isFinite {
                    if choice == nil || best[n][rest].cost < choice!.cost {
                        choice = best[n][rest]
                    }
                }
                row[rest] = choice?.route
            }
            table.append(row)
        }
        return table
    }

    // MARK: - Bewertung einer Route (kleiner = besser)

    private static func cost(of route: [Hit], rule: OutRule) -> Double {
        var c = Double(route.count) * 10
        for (index, hit) in route.enumerated() {
            c += index == route.count - 1 ? finishCost(hit, rule: rule) : setupCost(hit)
        }
        return c
    }

    private static let preferredDoubles: [Int: Double] = [
        16: 0, 20: 0.05, 8: 0.5, 18: 0.5, 12: 0.5, 10: 0.5,
        4: 1.0, 14: 1.0, 19: 1.0, 17: 1.0, 15: 1.0, 13: 1.0, 11: 1.0, 9: 1.0, 6: 1.0,
        7: 1.5, 5: 1.5, 3: 1.5, 2: 1.5, 1: 2.0
    ]

    private static func finishCost(_ hit: Hit, rule: OutRule) -> Double {
        switch hit.ring {
        case .double: return preferredDoubles[hit.number] ?? 1.5
        case .bull: return 3.5
        case .triple: return rule == .master ? 2.0 : 1.0
        case .single: return 0
        case .outerBull: return 2.5
        case .miss: return 100
        }
    }

    private static func setupCost(_ hit: Hit) -> Double {
        switch hit.ring {
        case .single: return 0.2
        case .outerBull: return 2.5
        case .bull: return 3.5
        case .double: return 3.0
        case .triple:
            switch hit.number {
            case 20, 19: return 0.8
            case 18, 17: return 1.2
            case 16: return 1.5
            case 15: return 1.8
            default: return 2.5 + Double(20 - hit.number) * 0.02
            }
        case .miss: return 100
        }
    }
}
