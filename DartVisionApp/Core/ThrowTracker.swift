import Foundation
import CoreGraphics

/// Eine Dart-Erkennung aus einem einzelnen Frame, bereits in Board-Koordinaten (mm).
nonisolated struct DartCandidate: Equatable, Sendable {
    var boardPoint: CGPoint
    var confidence: Double
    var imagePoint: CGPoint?
}

nonisolated struct FrameObservation: Sendable {
    var candidates: [DartCandidate]
    /// `false` = Board ist verdeckt (z. B. Person davor) – leere Frames zählen dann nicht als Takeout.
    var boardVisible: Bool?
    var timestamp: TimeInterval
}

/// Ein über mehrere Frames bestätigter Dart. Die Position ist der konfidenzgewichtete Mittelwert
/// aller Beobachtungen – das glättet das Rauschen der Spitzen-Erkennung.
nonisolated struct TrackedDart: Identifiable, Equatable, Sendable {
    let id: UUID
    var position: CGPoint
    var totalWeight: Double
    var observations: Int
    var maxConfidence: Double
    var isFrozen: Bool

    init(first candidate: DartCandidate) {
        id = UUID()
        position = candidate.boardPoint
        totalWeight = max(candidate.confidence, 0.05)
        observations = 1
        maxConfidence = candidate.confidence
        isFrozen = false
    }

    var hit: Hit { BoardGeometry.hit(at: position) }
    var wireDistance: Double { BoardGeometry.wireDistance(at: position) }
    /// Unsicher, wenn die Spitze sehr nah am Draht sitzt oder die KI wenig sicher war.
    var isUncertain: Bool { wireDistance < 1.5 || maxConfidence < 0.5 }

    mutating func add(_ candidate: DartCandidate) {
        let w = max(candidate.confidence, 0.05)
        let total = totalWeight + w
        position = CGPoint(
            x: (Double(position.x) * totalWeight + Double(candidate.boardPoint.x) * w) / total,
            y: (Double(position.y) * totalWeight + Double(candidate.boardPoint.y) * w) / total
        )
        totalWeight = total
        observations += 1
        maxConfidence = max(maxConfidence, candidate.confidence)
    }
}

nonisolated enum TrackerEvent: Equatable, Sendable {
    /// Neuer Dart bestätigt.
    case dartAdded(TrackedDart)
    /// Weitere Beobachtungen haben die Wertung eines Darts geändert.
    case dartRefined(TrackedDart)
    /// Board ist (wieder) leer – Darts wurden gezogen.
    case boardCleared(dartsOnBoard: Int)
}

nonisolated struct ThrowTrackerConfig: Equatable, Sendable {
    var minConfidence: Double = 0.35
    /// Abstand (mm), bis zu dem zwei Erkennungen als derselbe Dart gelten.
    var matchRadius: Double = 10
    /// Doppelte Erkennungen im selben Frame zusammenfassen (mm).
    var duplicateRadius: Double = 4
    /// So oft muss ein neuer Dart gesehen werden, bevor er zählt.
    var requiredObservations: Int = 2
    /// Ab dieser Konfidenz reicht eine einzige Beobachtung.
    var instantConfidence: Double = 0.9
    /// Leere Frames in Folge, bis "Darts gezogen" erkannt wird …
    var emptyFramesForTakeout: Int = 3
    /// … und Mindestdauer der Leere in Sekunden.
    var emptyDurationForTakeout: TimeInterval = 1.0
    var maxDartsPerTurn: Int = 3
    /// Nach so vielen Beobachtungen wird die Position nicht mehr verändert.
    var refineLimit: Int = 8
    /// Zuordnungsradius für bereits bestätigte Darts (mm). Bewusst kleiner als `matchRadius`:
    /// Ein zweiter Dart direkt daneben (enge Gruppe) wird so als neuer Dart erkannt,
    /// statt die Position des ersten zu verfälschen.
    var refineRadius: Double = 6
}

/// Verfolgt Darts über aufeinanderfolgende Frames:
/// - neue Darts erst nach mehrfacher Bestätigung zählen (gegen Fehlerkennungen),
/// - verdeckte Darts bleiben erhalten (später geworfene Darts verdecken oft frühere),
/// - "Board leer" erkennt das Ziehen der Darts und beendet den Zug.
nonisolated struct ThrowTracker: Sendable {

    nonisolated enum Phase: Equatable, Sendable {
        case collecting
        case waitingForTakeout
    }

    nonisolated private struct PendingDart: Sendable {
        var dart: TrackedDart
        var seenThisFrame: Bool
        var misses: Int
    }

    nonisolated private struct IgnoredSpot: Sendable {
        var position: CGPoint
        var misses: Int
    }

    var config: ThrowTrackerConfig
    private(set) var phase: Phase = .collecting
    private(set) var darts: [TrackedDart] = []
    /// Gültige Erkennungen des letzten Frames (für "Weiter" bei steckenden Darts).
    private(set) var lastCandidates: [DartCandidate] = []
    private var pending: [PendingDart] = []
    private var ignored: [IgnoredSpot] = []
    private var emptyStreak = 0
    private var emptySince: TimeInterval?

    init(config: ThrowTrackerConfig = ThrowTrackerConfig()) {
        self.config = config
    }

    var isEmpty: Bool { darts.isEmpty && pending.isEmpty }

    // MARK: - Frame verarbeiten

    mutating func process(_ observation: FrameObservation) -> [TrackerEvent] {
        var events: [TrackerEvent] = []
        let valid = observation.candidates.filter {
            $0.confidence >= config.minConfidence &&
            BoardGeometry.radius(of: $0.boardPoint) <= BoardGeometry.surroundRadius
        }
        let merged = Self.mergeDuplicates(valid, radius: config.duplicateRadius)
        lastCandidates = merged

        if merged.isEmpty {
            if observation.boardVisible != false {
                emptyStreak += 1
                if emptySince == nil { emptySince = observation.timestamp }
            }
            for i in pending.indices { pending[i].misses += 1 }
            pending.removeAll { $0.misses >= 2 }

            let longEnough = observation.timestamp - (emptySince ?? observation.timestamp) >= config.emptyDurationForTakeout
            if emptyStreak >= config.emptyFramesForTakeout && longEnough {
                ignored.removeAll()
                if phase == .waitingForTakeout || !darts.isEmpty {
                    events.append(.boardCleared(dartsOnBoard: darts.count))
                    startNewTurn()
                }
            }
            return events
        }

        emptyStreak = 0
        emptySince = nil
        let candidates = filterIgnored(merged)
        guard phase == .collecting, !candidates.isEmpty else { return events }

        // 1. Bekannte Darts wiederfinden und Position verfeinern
        let pairs = Self.greedyMatch(darts.map(\.position), candidates.map(\.boardPoint), radius: config.refineRadius)
        var usedCandidates = Set<Int>()
        for (di, ci) in pairs {
            usedCandidates.insert(ci)
            guard !darts[di].isFrozen else { continue }
            let oldHit = darts[di].hit
            darts[di].add(candidates[ci])
            if darts[di].observations >= config.refineLimit { darts[di].isFrozen = true }
            if darts[di].hit != oldHit { events.append(.dartRefined(darts[di])) }
        }

        // 2. Unbekannte Erkennungen als Kandidaten sammeln
        let rest = candidates.indices.filter { !usedCandidates.contains($0) }.map { candidates[$0] }
        for i in pending.indices { pending[i].seenThisFrame = false }
        let pendingPairs = Self.greedyMatch(pending.map(\.dart.position), rest.map(\.boardPoint), radius: config.matchRadius)
        var usedRest = Set<Int>()
        for (pi, ci) in pendingPairs {
            pending[pi].dart.add(rest[ci])
            pending[pi].seenThisFrame = true
            pending[pi].misses = 0
            usedRest.insert(ci)
        }
        for (ci, candidate) in rest.enumerated() where !usedRest.contains(ci) {
            pending.append(PendingDart(dart: TrackedDart(first: candidate), seenThisFrame: true, misses: 0))
        }
        for i in pending.indices where !pending[i].seenThisFrame { pending[i].misses += 1 }
        pending.removeAll { $0.misses >= 2 }

        // 3. Ausreichend bestätigte Kandidaten übernehmen
        var stillPending: [PendingDart] = []
        for p in pending {
            let confirmed = p.dart.observations >= config.requiredObservations ||
                p.dart.maxConfidence >= config.instantConfidence
            guard confirmed else {
                stillPending.append(p)
                continue
            }
            guard darts.count < config.maxDartsPerTurn else { continue }
            // Ältere Darts werden ab jetzt nicht mehr verändert: der neue Dart kann sie verdecken.
            for i in darts.indices { darts[i].isFrozen = true }
            darts.append(p.dart)
            events.append(.dartAdded(p.dart))
        }
        pending = stillPending
        return events
    }

    // MARK: - Steuerung durch die Spiellogik

    /// Zug ist laut Regelwerk beendet (3 Darts, Bust, Checkout) – jetzt nur noch auf das Ziehen warten.
    mutating func turnEnded() {
        phase = .waitingForTakeout
        pending.removeAll()
        emptyStreak = 0
        emptySince = nil
    }

    /// Neuer Zug. Mit `ignoringVisible` werden aktuell steckende Darts ignoriert
    /// (z. B. wenn "Weiter" gedrückt wurde, ohne die Darts zu ziehen).
    mutating func startNewTurn(ignoringVisible: Bool = false) {
        if ignoringVisible {
            let spots = darts.map(\.position) + lastCandidates.map(\.boardPoint)
            ignored = spots.map { IgnoredSpot(position: $0, misses: 0) }
        } else {
            ignored.removeAll()
        }
        darts.removeAll()
        pending.removeAll()
        phase = .collecting
        emptyStreak = 0
        emptySince = nil
    }

    /// Der Spieler hat einen erkannten Dart verworfen (Undo/Korrektur) – Position künftig ignorieren.
    mutating func reject(id: UUID) {
        guard let index = darts.firstIndex(where: { $0.id == id }) else { return }
        let removed = darts.remove(at: index)
        ignored.append(IgnoredSpot(position: removed.position, misses: 0))
        phase = .collecting
    }

    /// Zug wurde manuell wieder geöffnet (Undo) – weiter Darts sammeln.
    mutating func resumeCollecting() {
        phase = .collecting
    }

    // MARK: - Hilfsfunktionen

    private mutating func filterIgnored(_ candidates: [DartCandidate]) -> [DartCandidate] {
        guard !ignored.isEmpty else { return candidates }
        let pairs = Self.greedyMatch(ignored.map(\.position), candidates.map(\.boardPoint), radius: config.matchRadius)
        var matchedSpots = Set<Int>()
        var matchedCandidates = Set<Int>()
        for (si, ci) in pairs {
            matchedSpots.insert(si)
            matchedCandidates.insert(ci)
        }
        for i in ignored.indices {
            if matchedSpots.contains(i) { ignored[i].misses = 0 } else { ignored[i].misses += 1 }
        }
        ignored.removeAll { $0.misses >= 3 }
        return candidates.indices.filter { !matchedCandidates.contains($0) }.map { candidates[$0] }
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(Double(a.x - b.x), Double(a.y - b.y))
    }

    /// Globale Zuordnung nach kleinstem Abstand (wichtig bei eng gruppierten Darts, z. B. im T20).
    static func greedyMatch(_ a: [CGPoint], _ b: [CGPoint], radius: Double) -> [(Int, Int)] {
        var pairs: [(distance: Double, i: Int, j: Int)] = []
        for (i, p) in a.enumerated() {
            for (j, q) in b.enumerated() {
                let d = distance(p, q)
                if d <= radius { pairs.append((d, i, j)) }
            }
        }
        pairs.sort { $0.distance < $1.distance }
        var usedA = Set<Int>()
        var usedB = Set<Int>()
        var result: [(Int, Int)] = []
        for pair in pairs where !usedA.contains(pair.i) && !usedB.contains(pair.j) {
            usedA.insert(pair.i)
            usedB.insert(pair.j)
            result.append((pair.i, pair.j))
        }
        return result
    }

    /// Fasst Erkennungen zusammen, die praktisch am selben Ort liegen (höchste Konfidenz gewinnt).
    static func mergeDuplicates(_ candidates: [DartCandidate], radius: Double) -> [DartCandidate] {
        var kept: [DartCandidate] = []
        for c in candidates.sorted(by: { $0.confidence > $1.confidence }) {
            if !kept.contains(where: { distance($0.boardPoint, c.boardPoint) < radius }) {
                kept.append(c)
            }
        }
        return kept
    }
}
