import Foundation
import CoreGraphics

// MARK: - Regeln

nonisolated enum OutRule: String, Codable, CaseIterable, Identifiable, Sendable {
    case straight, double, master

    var id: String { rawValue }

    var title: String {
        switch self {
        case .straight: return "Single Out"
        case .double: return "Double Out"
        case .master: return "Master Out"
        }
    }

    func allowsFinish(with hit: Hit) -> Bool {
        switch self {
        case .straight: return hit.ring != .miss
        case .double: return hit.isDouble
        case .master: return hit.isDouble || hit.isTriple
        }
    }
}

nonisolated enum InRule: String, Codable, CaseIterable, Identifiable, Sendable {
    case straight, double

    var id: String { rawValue }

    var title: String {
        switch self {
        case .straight: return "Single In"
        case .double: return "Double In"
        }
    }

    func opens(with hit: Hit) -> Bool {
        self == .straight || hit.isDouble
    }
}

nonisolated struct X01Settings: Codable, Equatable, Sendable {
    var startScore: Int = 501
    var inRule: InRule = .straight
    var outRule: OutRule = .double
    /// Best of N Legs (1, 3, 5, 7 …).
    var bestOfLegs: Int = 1

    var legsToWin: Int { max(1, bestOfLegs / 2 + 1) }

    var summary: String {
        var parts = ["\(startScore)", outRule.title]
        if inRule == .double { parts.append(InRule.double.title) }
        if bestOfLegs > 1 { parts.append("Best of \(bestOfLegs)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Würfe, Züge, Legs

nonisolated enum DartSource: String, Codable, Sendable {
    case camera      // von der KI erkannt
    case manual      // manuell eingegeben
    case corrected   // KI-Wert vom Spieler korrigiert
    case autoMiss    // automatisch aufgefüllt (Zug ohne 3 erkannte Darts beendet)
}

nonisolated struct DartThrow: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var hit: Hit
    var source: DartSource
    var confidence: Double?
    /// Position auf dem Board in mm (nur bei Kamera-Darts oder Board-Eingabe).
    var boardPoint: CGPoint?
    /// Nahe am Draht oder niedrige Konfidenz → im UI markieren.
    var isUncertain: Bool = false

    init(hit: Hit, source: DartSource, confidence: Double? = nil, boardPoint: CGPoint? = nil, isUncertain: Bool = false) {
        self.hit = hit
        self.source = source
        self.confidence = confidence
        self.boardPoint = boardPoint
        self.isUncertain = isUncertain
    }
}

nonisolated struct Turn: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    let playerIndex: Int
    var darts: [DartThrow]
    /// Zug wurde vor dem 3. Dart beendet (Takeout erkannt / "Weiter" gedrückt).
    var endedEarly: Bool = false

    init(playerIndex: Int, darts: [DartThrow] = [], endedEarly: Bool = false) {
        self.playerIndex = playerIndex
        self.darts = darts
        self.endedEarly = endedEarly
    }

    var rawPoints: Int { darts.reduce(0) { $0 + $1.hit.points } }
}

nonisolated struct Leg: Codable, Equatable, Sendable {
    let startingPlayer: Int
    var turns: [Turn] = []
}

nonisolated enum BustReason: String, Codable, Equatable, Sendable {
    case overshot
    case leftOne
    case invalidFinish

    var message: String {
        switch self {
        case .overshot: return "Überworfen"
        case .leftOne: return "Überworfen – Rest 1"
        case .invalidFinish: return "Kein gültiges Finish"
        }
    }
}

nonisolated struct TurnResult: Equatable, Sendable {
    var startRemaining: Int
    var endRemaining: Int
    /// Gewertete Punkte (0 bei Bust).
    var scored: Int
    var bust: BustReason?
    var isCheckout: Bool
    var openedAfter: Bool
    var isClosed: Bool
    /// Darts, die gezählt werden (bis einschließlich Bust/Checkout).
    var countedDarts: Int

    var isBust: Bool { bust != nil }
}

// MARK: - Auswertung eines Zugs

nonisolated enum X01Rules {

    static func evaluate(_ turn: Turn, startRemaining: Int, opened: Bool, settings: X01Settings) -> TurnResult {
        var remaining = startRemaining
        var isOpen = opened

        for (index, dart) in turn.darts.enumerated() {
            let hit = dart.hit
            if !isOpen {
                guard settings.inRule.opens(with: hit) else { continue }
                isOpen = true
            }
            let next = remaining - hit.points
            if next < 0 {
                return bustResult(.overshot, startRemaining: startRemaining, opened: opened, dartsUsed: index + 1)
            }
            if next == 0 {
                guard settings.outRule.allowsFinish(with: hit) else {
                    return bustResult(.invalidFinish, startRemaining: startRemaining, opened: opened, dartsUsed: index + 1)
                }
                return TurnResult(startRemaining: startRemaining, endRemaining: 0, scored: startRemaining,
                                  bust: nil, isCheckout: true, openedAfter: true, isClosed: true,
                                  countedDarts: index + 1)
            }
            if next == 1 && settings.outRule != .straight {
                return bustResult(.leftOne, startRemaining: startRemaining, opened: opened, dartsUsed: index + 1)
            }
            remaining = next
        }

        return TurnResult(startRemaining: startRemaining, endRemaining: remaining,
                          scored: startRemaining - remaining, bust: nil, isCheckout: false,
                          openedAfter: isOpen, isClosed: turn.darts.count >= 3 || turn.endedEarly,
                          countedDarts: turn.darts.count)
    }

    private static func bustResult(_ reason: BustReason, startRemaining: Int, opened: Bool, dartsUsed: Int) -> TurnResult {
        // Bei Bust fällt der Rest auf den Stand vor dem Zug zurück – inklusive "Double In"-Status.
        TurnResult(startRemaining: startRemaining, endRemaining: startRemaining, scored: 0,
                   bust: reason, isCheckout: false, openedAfter: opened, isClosed: true,
                   countedDarts: dartsUsed)
    }
}

// MARK: - Auswertungsergebnisse

nonisolated struct LegEvaluation: Equatable, Sendable {
    var remaining: [Int]
    var opened: [Bool]
    /// Ein Ergebnis pro Zug (bis einschließlich Checkout).
    var results: [TurnResult]
    var winner: Int?
}

nonisolated struct PlayerStats: Equatable, Sendable {
    var points = 0
    var darts = 0
    var bestTurn = 0
    var count180 = 0
    var count140Plus = 0
    var count100Plus = 0
    var highestCheckout = 0
    var legsWon = 0

    var threeDartAverage: Double {
        darts > 0 ? Double(points) * 3 / Double(darts) : 0
    }
}

nonisolated enum MatchPhase: Equatable, Sendable {
    case throwing(player: Int, dartsLeft: Int)
    case legWon(winner: Int)
    case matchWon(winner: Int)
}

nonisolated struct MatchSnapshot: Equatable, Sendable {
    var phase: MatchPhase
    var legIndex: Int
    var legsWon: [Int]
    var remaining: [Int]
    var opened: [Bool]
    var stats: [PlayerStats]
    var currentPlayer: Int
    /// Offener Zug (mind. 1 Dart, noch nicht abgeschlossen).
    var openTurn: Turn?
    var openTurnResult: TurnResult?
    /// Zuletzt abgeschlossener Zug im aktuellen Leg.
    var lastClosedTurn: Turn?
    var lastClosedTurnResult: TurnResult?

    var matchWinner: Int? {
        if case .matchWon(let winner) = phase { return winner }
        return nil
    }

    var legWinner: Int? {
        switch phase {
        case .legWon(let winner), .matchWon(let winner): return winner
        case .throwing: return nil
        }
    }

    var dartsLeft: Int {
        if case .throwing(_, let left) = phase { return left }
        return 0
    }
}

nonisolated enum AddDartOutcome: Equatable, Sendable {
    case continued(dartsLeft: Int)
    case turnComplete(scored: Int)
    case bust(BustReason)
    case legWon(player: Int)
    case matchWon(player: Int)
    case rejected
}

nonisolated enum UndoOutcome: Equatable, Sendable {
    case removedDart(DartThrow)
    case reopenedTurn
    case nothing
}

// MARK: - Match

/// Ereignisbasiertes X01-Match: gespeichert werden nur die geworfenen Darts,
/// alle Stände (Rest, Bust, Legs, Statistik) werden daraus berechnet.
/// Dadurch bleiben Korrekturen und Undo immer konsistent.
nonisolated struct X01Match: Codable, Equatable, Sendable {
    let settings: X01Settings
    let players: [String]
    private(set) var legs: [Leg]

    init(settings: X01Settings, players: [String]) {
        self.settings = settings
        self.players = players.isEmpty ? ["Spieler 1"] : players
        self.legs = [Leg(startingPlayer: 0)]
    }

    private var currentLeg: Leg {
        get { legs[legs.count - 1] }
        set { legs[legs.count - 1] = newValue }
    }

    // MARK: Auswertung

    func evaluate(_ leg: Leg) -> LegEvaluation {
        var remaining = Array(repeating: settings.startScore, count: players.count)
        var opened = Array(repeating: settings.inRule == .straight, count: players.count)
        var results: [TurnResult] = []
        var winner: Int?

        for turn in leg.turns {
            if winner != nil { break }
            let p = min(max(turn.playerIndex, 0), players.count - 1)
            let result = X01Rules.evaluate(turn, startRemaining: remaining[p], opened: opened[p], settings: settings)
            results.append(result)
            remaining[p] = result.endRemaining
            opened[p] = result.openedAfter
            if result.isCheckout { winner = p }
        }
        return LegEvaluation(remaining: remaining, opened: opened, results: results, winner: winner)
    }

    func snapshot() -> MatchSnapshot {
        var legsWon = Array(repeating: 0, count: players.count)
        var stats = Array(repeating: PlayerStats(), count: players.count)

        for leg in legs {
            let evaluation = evaluate(leg)
            for (index, result) in evaluation.results.enumerated() {
                let p = min(max(leg.turns[index].playerIndex, 0), players.count - 1)
                stats[p].darts += result.countedDarts
                if !result.isBust { stats[p].points += result.scored }
                if result.isClosed && !result.isBust {
                    stats[p].bestTurn = max(stats[p].bestTurn, result.scored)
                    if result.scored == 180 {
                        stats[p].count180 += 1
                    } else if result.scored >= 140 {
                        stats[p].count140Plus += 1
                    } else if result.scored >= 100 {
                        stats[p].count100Plus += 1
                    }
                }
                if result.isCheckout {
                    stats[p].highestCheckout = max(stats[p].highestCheckout, result.startRemaining)
                }
            }
            if let winner = evaluation.winner { legsWon[winner] += 1 }
        }
        for i in stats.indices { stats[i].legsWon = legsWon[i] }

        let leg = currentLeg
        let evaluation = evaluate(leg)

        var openTurn: Turn?
        var openTurnResult: TurnResult?
        if let last = leg.turns.last, let lastResult = evaluation.results.last,
           evaluation.results.count == leg.turns.count, !lastResult.isClosed {
            openTurn = last
            openTurnResult = lastResult
        }

        var lastClosedTurn: Turn?
        var lastClosedTurnResult: TurnResult?
        for index in stride(from: evaluation.results.count - 1, through: 0, by: -1) where evaluation.results[index].isClosed {
            lastClosedTurn = leg.turns[index]
            lastClosedTurnResult = evaluation.results[index]
            break
        }

        let phase: MatchPhase
        let currentPlayer: Int
        if let winner = evaluation.winner {
            phase = legsWon[winner] >= settings.legsToWin ? .matchWon(winner: winner) : .legWon(winner: winner)
            currentPlayer = winner
        } else if let openTurn {
            currentPlayer = openTurn.playerIndex
            phase = .throwing(player: currentPlayer, dartsLeft: max(0, 3 - openTurn.darts.count))
        } else {
            currentPlayer = (leg.startingPlayer + leg.turns.count) % players.count
            phase = .throwing(player: currentPlayer, dartsLeft: 3)
        }

        return MatchSnapshot(
            phase: phase,
            legIndex: legs.count - 1,
            legsWon: legsWon,
            remaining: evaluation.remaining,
            opened: evaluation.opened,
            stats: stats,
            currentPlayer: currentPlayer,
            openTurn: openTurn,
            openTurnResult: openTurnResult,
            lastClosedTurn: lastClosedTurn,
            lastClosedTurnResult: lastClosedTurnResult
        )
    }

    func turn(withID id: UUID) -> Turn? {
        for leg in legs.reversed() {
            if let turn = leg.turns.first(where: { $0.id == id }) { return turn }
        }
        return nil
    }

    /// Ergebnis eines Zugs (`nil`, wenn der Zug nach einem Checkout liegt oder nicht existiert).
    func result(forTurn turnID: UUID) -> TurnResult? {
        for leg in legs.reversed() {
            guard let index = leg.turns.firstIndex(where: { $0.id == turnID }) else { continue }
            let evaluation = evaluate(leg)
            return index < evaluation.results.count ? evaluation.results[index] : nil
        }
        return nil
    }

    // MARK: Mutationen

    @discardableResult
    mutating func addDart(_ dart: DartThrow) -> AddDartOutcome {
        let before = snapshot()
        guard case .throwing(let player, _) = before.phase else { return .rejected }

        var leg = currentLeg
        let turnIndex: Int
        if let open = before.openTurn, let index = leg.turns.lastIndex(where: { $0.id == open.id }) {
            leg.turns[index].darts.append(dart)
            turnIndex = index
        } else {
            leg.turns.append(Turn(playerIndex: player, darts: [dart]))
            turnIndex = leg.turns.count - 1
        }
        currentLeg = leg

        let evaluation = evaluate(leg)
        guard turnIndex < evaluation.results.count else { return .rejected }
        let result = evaluation.results[turnIndex]

        if result.isCheckout {
            let after = snapshot()
            if case .matchWon(let winner) = after.phase { return .matchWon(player: winner) }
            return .legWon(player: player)
        }
        if let reason = result.bust { return .bust(reason) }
        if result.isClosed { return .turnComplete(scored: result.scored) }
        return .continued(dartsLeft: max(0, 3 - leg.turns[turnIndex].darts.count))
    }

    /// Beendet den laufenden Zug. Fehlende Darts zählen als Miss.
    @discardableResult
    mutating func endTurn() -> TurnResult? {
        let before = snapshot()
        guard case .throwing(let player, _) = before.phase else { return nil }

        var leg = currentLeg
        let turnIndex: Int
        if let open = before.openTurn, let index = leg.turns.lastIndex(where: { $0.id == open.id }) {
            while leg.turns[index].darts.count < 3 {
                leg.turns[index].darts.append(DartThrow(hit: .miss, source: .autoMiss))
            }
            leg.turns[index].endedEarly = true
            turnIndex = index
        } else {
            let misses = (0..<3).map { _ in DartThrow(hit: .miss, source: .autoMiss) }
            leg.turns.append(Turn(playerIndex: player, darts: misses, endedEarly: true))
            turnIndex = leg.turns.count - 1
        }
        currentLeg = leg
        let evaluation = evaluate(leg)
        return turnIndex < evaluation.results.count ? evaluation.results[turnIndex] : nil
    }

    /// Startet nach einem gewonnenen Leg das nächste (Anwurf wechselt).
    @discardableResult
    mutating func startNextLeg() -> Bool {
        guard case .legWon = snapshot().phase else { return false }
        let nextStarter = (currentLeg.startingPlayer + 1) % players.count
        legs.append(Leg(startingPlayer: nextStarter))
        return true
    }

    /// Nimmt den letzten Dart zurück (auch über Zug- und Leg-Grenzen hinweg).
    @discardableResult
    mutating func undo() -> UndoOutcome {
        if legs.count > 1 && currentLeg.turns.isEmpty {
            legs.removeLast()
        }
        var leg = currentLeg
        guard var turn = leg.turns.popLast() else { return .nothing }

        var outcome = UndoOutcome.nothing
        if turn.endedEarly {
            turn.endedEarly = false
            let countBefore = turn.darts.count
            turn.darts.removeAll { $0.source == .autoMiss }
            if turn.darts.count != countBefore {
                outcome = .reopenedTurn
            } else if let removed = turn.darts.popLast() {
                outcome = .removedDart(removed)
            }
        } else if let removed = turn.darts.popLast() {
            outcome = .removedDart(removed)
        }

        if !turn.darts.isEmpty { leg.turns.append(turn) }
        currentLeg = leg
        return outcome
    }

    /// Ersetzt die Darts eines Zugs im aktuellen Leg (Korrektur). Wird der zuletzt gewonnene
    /// Leg-Checkout korrigiert, wird ein noch leeres Folge-Leg verworfen.
    @discardableResult
    mutating func replaceDarts(inTurn turnID: UUID, with darts: [DartThrow]) -> Bool {
        if legs.count > 1, currentLeg.turns.isEmpty,
           legs[legs.count - 2].turns.contains(where: { $0.id == turnID }) {
            legs.removeLast()
        }
        var leg = currentLeg
        guard let index = leg.turns.firstIndex(where: { $0.id == turnID }) else { return false }

        let newDarts = Array(darts.prefix(3))
        let isLastTurn = index == leg.turns.count - 1
        if newDarts.isEmpty && isLastTurn {
            leg.turns.remove(at: index)
        } else {
            leg.turns[index].darts = newDarts
            if isLastTurn {
                leg.turns[index].endedEarly = false
            } else {
                // Vergangene Züge bleiben abgeschlossen: fehlende Darts als Miss auffüllen.
                while leg.turns[index].darts.count < 3 {
                    leg.turns[index].darts.append(DartThrow(hit: .miss, source: .autoMiss))
                }
            }
        }
        currentLeg = leg
        trimTurnsAfterCheckout()
        return true
    }

    /// Aktualisiert einen einzelnen Dart (z. B. wenn die KI ihre Wertung präzisiert).
    @discardableResult
    mutating func updateDart(id: UUID, hit: Hit, boardPoint: CGPoint?, isUncertain: Bool) -> Bool {
        var leg = currentLeg
        for t in leg.turns.indices {
            if let d = leg.turns[t].darts.firstIndex(where: { $0.id == id }) {
                leg.turns[t].darts[d].hit = hit
                leg.turns[t].darts[d].boardPoint = boardPoint
                leg.turns[t].darts[d].isUncertain = isUncertain
                currentLeg = leg
                trimTurnsAfterCheckout()
                return true
            }
        }
        return false
    }

    private mutating func trimTurnsAfterCheckout() {
        var leg = currentLeg
        let evaluation = evaluate(leg)
        if evaluation.winner != nil, evaluation.results.count < leg.turns.count {
            leg.turns.removeSubrange(evaluation.results.count..<leg.turns.count)
            currentLeg = leg
        }
    }
}
