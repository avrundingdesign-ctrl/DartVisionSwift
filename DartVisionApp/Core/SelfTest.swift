import Foundation
import CoreGraphics

/// Selbsttest der Kernlogik (Geometrie, Homographie, Regeln, Checkout, Tracker).
/// Läuft direkt in der App unter Einstellungen → Diagnose – ohne separates Test-Target.
nonisolated enum SelfTest {

    nonisolated struct Result: Identifiable, Sendable {
        let id = UUID()
        let group: String
        let name: String
        let passed: Bool
        let detail: String
    }

    static func runAll() -> [Result] {
        var results: [Result] = []
        var group = ""

        func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
            results.append(Result(group: group, name: name, passed: condition, detail: condition ? "" : detail()))
        }

        func dart(_ hit: Hit) -> DartThrow { DartThrow(hit: hit, source: .manual) }

        // MARK: Geometrie
        group = "Board-Geometrie"
        check("T20 in der Mitte des Triple-Rings", BoardGeometry.hit(at: BoardGeometry.point(radius: 103, angleDegrees: 0)) == .triple(20))
        check("D20 außen oben", BoardGeometry.hit(at: CGPoint(x: 0, y: 166)) == .double(20))
        check("Bull und 25", BoardGeometry.hit(at: .zero) == .bull && BoardGeometry.hit(at: CGPoint(x: 10, y: 0)) == .outerBull)
        check("6 rechts, 3 unten, 11 links",
              BoardGeometry.hit(at: CGPoint(x: 120, y: 0)) == .single(6) &&
              BoardGeometry.hit(at: CGPoint(x: 0, y: -120)) == .single(3) &&
              BoardGeometry.hit(at: CGPoint(x: -120, y: 0)) == .single(11))
        check("Segmentgrenze 5 | 20",
              BoardGeometry.hit(at: BoardGeometry.point(radius: 120, angleDegrees: 350.9)) == .single(5) &&
              BoardGeometry.hit(at: BoardGeometry.point(radius: 120, angleDegrees: 351.1)) == .single(20))
        check("Außerhalb des Doppelrings = Miss", BoardGeometry.hit(at: CGPoint(x: 0, y: 175)) == .miss)
        let wire = BoardGeometry.wireDistance(at: BoardGeometry.point(radius: 103, angleDegrees: 0))
        check("Drahtabstand T20-Mitte = 4 mm", abs(wire - 4) < 0.001, "gemessen \(wire)")

        // MARK: Homographie & Kalibrierung
        group = "Kalibrierung"
        let boardToImage = Matrix3([1.2, 0.1, 500, -0.05, -0.9, 400, 0.0002, -0.0001, 1])
        let imagePoints = BoardGeometry.calibrationPoints.compactMap { boardToImage.apply($0) }
        if let keypoints = BoardKeypoints(points: imagePoints),
           let calibration = BoardCalibration(keypoints: keypoints, imageSize: CGSize(width: 1000, height: 800)) {
            let probe = BoardGeometry.point(radius: 103, angleDegrees: 0)
            let roundTrip = boardToImage.apply(probe).flatMap { calibration.boardPoint(fromImage: $0) }
            let error = roundTrip.map { hypot($0.x - probe.x, $0.y - probe.y) } ?? .infinity
            check("Perspektive wird exakt zurückgerechnet", error < 0.001, "Fehler \(error) mm")
            check("Auflösung wird geschätzt", calibration.pixelsPerMillimeter > 0.8 && calibration.pixelsPerMillimeter < 1.3,
                  "\(calibration.pixelsPerMillimeter) px/mm")
        } else {
            check("Kalibrierung aus synthetischen Punkten", false, "BoardCalibration ist nil")
        }
        if let swapped = BoardKeypoints(points: Array(imagePoints.reversed())) {
            check("Vertauschte Punkte werden abgelehnt",
                  BoardCalibration(keypoints: swapped, imageSize: CGSize(width: 1000, height: 800)) == nil)
        }

        // MARK: X01-Regeln
        group = "X01-Regeln"
        var match = X01Match(settings: X01Settings(startScore: 101, inRule: .straight, outRule: .double, bestOfLegs: 1),
                             players: ["A", "B"])
        match.addDart(dart(.triple(20)))
        match.addDart(dart(.single(1)))
        let third = match.addDart(dart(.single(20)))
        check("Zug endet nach drei Darts", third == .turnComplete(scored: 81) &&
              match.snapshot().remaining[0] == 20 && match.snapshot().currentPlayer == 1)

        match.addDart(dart(.triple(20)))
        let overshot = match.addDart(dart(.triple(20)))
        check("Überworfen setzt Rest zurück", overshot == .bust(.overshot) &&
              match.snapshot().remaining[1] == 101 && match.snapshot().currentPlayer == 0)

        let noDouble = match.addDart(dart(.single(20)))
        check("Double Out verlangt ein Doppel", noDouble == .bust(.invalidFinish) && match.snapshot().remaining[0] == 20)

        match.addDart(dart(.triple(20)))
        let leftOne = match.addDart(dart(.double(20)))
        check("Rest 1 ist überworfen", leftOne == .bust(.leftOne) && match.snapshot().remaining[1] == 101)

        let checkout = match.addDart(dart(.double(10)))
        check("Checkout gewinnt", checkout == .matchWon(player: 0))

        match.undo()
        check("Undo nimmt den Checkout zurück", match.snapshot().matchWinner == nil && match.snapshot().remaining[0] == 20)

        match.addDart(dart(.single(5)))
        let ended = match.endTurn()
        check("Zug beenden füllt mit Miss auf", ended?.scored == 5 && ended?.countedDarts == 3 &&
              match.snapshot().currentPlayer == 1)

        var doubleIn = X01Match(settings: X01Settings(startScore: 301, inRule: .double, outRule: .double, bestOfLegs: 1),
                                players: ["A"])
        doubleIn.addDart(dart(.triple(20)))
        doubleIn.addDart(dart(.double(10)))
        doubleIn.addDart(dart(.single(20)))
        check("Double In zählt erst ab dem Doppel", doubleIn.snapshot().remaining[0] == 261,
              "Rest \(doubleIn.snapshot().remaining[0])")

        var legs = X01Match(settings: X01Settings(startScore: 40, inRule: .straight, outRule: .double, bestOfLegs: 3),
                            players: ["A", "B"])
        let leg1 = legs.addDart(dart(.double(20)))
        legs.startNextLeg()
        check("Leg-Gewinn und Anwurfwechsel", leg1 == .legWon(player: 0) && legs.snapshot().currentPlayer == 1)
        legs.addDart(dart(.double(20)))
        legs.startNextLeg()
        let decider = legs.addDart(dart(.double(20)))
        check("Best of 3 nach zwei Legs entschieden", decider == .matchWon(player: 0) && legs.snapshot().legsWon == [2, 1])

        var correction = X01Match(settings: X01Settings(startScore: 501), players: ["A"])
        correction.addDart(dart(.triple(20)))
        correction.addDart(dart(.triple(20)))
        correction.addDart(dart(.single(20)))
        if let turn = correction.snapshot().lastClosedTurn {
            var darts = turn.darts
            darts[2].hit = .triple(20)
            correction.replaceDarts(inTurn: turn.id, with: darts)
            let snapshot = correction.snapshot()
            check("Korrektur rechnet alles neu", snapshot.remaining[0] == 321 && snapshot.stats[0].count180 == 1,
                  "Rest \(snapshot.remaining[0])")
        } else {
            check("Korrektur rechnet alles neu", false, "kein abgeschlossener Zug")
        }

        // MARK: Checkout
        group = "Checkout-Rechner"
        check("170 = T20 T20 Bull", CheckoutCalculator.route(for: 170, outRule: .double) == [.triple(20), .triple(20), .bull])
        check("169 ist nicht checkbar", CheckoutCalculator.route(for: 169, outRule: .double) == nil)
        check("100 = T20 D20", CheckoutCalculator.route(for: 100, outRule: .double) == [.triple(20), .double(20)])
        check("Ein Dart: 50 = Bull", CheckoutCalculator.route(for: 50, dartsLeft: 1, outRule: .double) == [.bull])
        check("Ein Dart: 41 geht nicht", CheckoutCalculator.route(for: 41, dartsLeft: 1, outRule: .double) == nil)
        check("Master Out: 60 = T20", CheckoutCalculator.route(for: 60, dartsLeft: 1, outRule: .master) == [.triple(20)])

        // MARK: Tracker
        group = "Wurf-Tracker"
        var tracker = ThrowTracker()
        let first = DartCandidate(boardPoint: BoardGeometry.point(radius: 103, angleDegrees: 0), confidence: 0.8)
        let second = DartCandidate(boardPoint: BoardGeometry.point(radius: 103, angleDegrees: 4), confidence: 0.8)
        var events = tracker.process(FrameObservation(candidates: [first], boardVisible: true, timestamp: 0))
        check("Neuer Dart braucht Bestätigung", events.isEmpty)
        events = tracker.process(FrameObservation(candidates: [first], boardVisible: true, timestamp: 0.3))
        check("Bestätigt nach zwei Frames", events.count == 1 && tracker.darts.first?.hit == .triple(20))
        _ = tracker.process(FrameObservation(candidates: [first, second], boardVisible: true, timestamp: 0.6))
        events = tracker.process(FrameObservation(candidates: [first, second], boardVisible: true, timestamp: 0.9))
        check("Enge Gruppe: zweiter Dart 7 mm daneben", events.count == 1 && tracker.darts.count == 2,
              "\(tracker.darts.count) Darts")
        events = tracker.process(FrameObservation(candidates: [second], boardVisible: true, timestamp: 1.2))
        check("Verdeckter Dart bleibt erhalten", events.isEmpty && tracker.darts.count == 2)
        _ = tracker.process(FrameObservation(candidates: [], boardVisible: false, timestamp: 1.5))
        _ = tracker.process(FrameObservation(candidates: [], boardVisible: false, timestamp: 2.0))
        _ = tracker.process(FrameObservation(candidates: [], boardVisible: false, timestamp: 2.5))
        check("Verdecktes Board ist kein Takeout", tracker.darts.count == 2)
        _ = tracker.process(FrameObservation(candidates: [], boardVisible: true, timestamp: 3.0))
        _ = tracker.process(FrameObservation(candidates: [], boardVisible: true, timestamp: 3.5))
        events = tracker.process(FrameObservation(candidates: [], boardVisible: true, timestamp: 4.1))
        check("Leeres Board = Darts gezogen", events == [.boardCleared(dartsOnBoard: 2)] && tracker.darts.isEmpty)

        return results
    }
}
