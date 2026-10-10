import Foundation
import UIKit
import Observation
import CoreGraphics

/// Verbindet Spielregeln, Kamera, KI und Tracker zu einem laufenden Spiel.
///
/// Ablauf im Kamera-Modus:
/// 1. Gerät steht still → neuestes Videobild wird analysiert (lokal ca. alle 0,3 s).
/// 2. Der Tracker bestätigt neue Darts erst nach mehreren Frames und gibt sie an die Regeln weiter.
/// 3. Nach 3 Darts / Bust / Checkout wartet die Session, bis das Board leer ist (Darts gezogen),
///    dann ist der nächste Spieler dran. Werden Darts mit weniger als 3 Treffern gezogen,
///    zählen die fehlenden als Miss – ein Zug bleibt so nie mehr "hängen".
@Observable
final class GameSession {

    enum Status: Equatable {
        case manual
        case starting
        case watching
        case holdStill
        case pullDarts
        case recalibrating
        case paused
        case error(String)
    }

    enum Banner: Equatable {
        case bust(String)
        case oneEighty
        case info(String)
    }

    struct DisplayedTurn {
        let player: Int
        let darts: [DartThrow]
        let result: TurnResult?
        /// Abgeschlossener Zug, der noch angezeigt wird (z. B. bis die Darts gezogen sind).
        let isFinished: Bool
    }

    struct CorrectionEntry: Identifiable, Equatable {
        let id: UUID
        var hit: Hit
        var boardPoint: CGPoint?
    }

    let inputMode: InputMode
    private(set) var match: X01Match
    private(set) var snapshot: MatchSnapshot
    private(set) var status: Status
    private(set) var calibration: BoardCalibration?
    private(set) var liveDarts: [TrackedDart] = []
    private(set) var awaitingTakeout = false
    private(set) var isAnalyzing = false
    private(set) var lastAnalysisMilliseconds = 0
    private(set) var banner: Banner?
    private(set) var isPaused = false

    /// Wird nach jeder Änderung des Spielstands aufgerufen (Speichern zum Fortsetzen).
    @ObservationIgnored var onMatchChange: ((X01Match) -> Void)?

    @ObservationIgnored private var tracker: ThrowTracker
    @ObservationIgnored private let detector: (any DartDetector)?
    @ObservationIgnored private let camera: CameraController?
    @ObservationIgnored private let motion: MotionMonitor?
    @ObservationIgnored private let speech: SpeechCaller
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var engineDartForTrack: [UUID: UUID] = [:]
    @ObservationIgnored private var lastFrameTimestamp: TimeInterval = -1
    @ObservationIgnored private var lastCalibrationCheck = Date()
    @ObservationIgnored private var handledMovements = 0
    @ObservationIgnored private var turnFrames: [UUID: (data: Data, size: CGSize)] = [:]

    init(match: X01Match,
         inputMode: InputMode,
         calibration: BoardCalibration?,
         detector: (any DartDetector)?,
         camera: CameraController?,
         motion: MotionMonitor?,
         speech: SpeechCaller,
         settings: AppSettings) {
        self.match = match
        self.snapshot = match.snapshot()
        self.inputMode = inputMode
        self.calibration = calibration
        self.detector = detector
        self.camera = camera
        self.motion = motion
        self.speech = speech
        self.settings = settings

        var config = ThrowTrackerConfig()
        config.minConfidence = settings.minConfidence
        if detector?.cheapBoardCheck == false {
            // Server: weniger Frames pro Sekunde → sichere Erkennungen schneller übernehmen.
            config.instantConfidence = 0.75
            config.emptyFramesForTakeout = 2
        }
        self.tracker = ThrowTracker(config: config)
        self.status = inputMode == .camera ? .starting : .manual
    }

    // MARK: - Abgeleitete Werte für die Oberfläche

    var players: [String] { match.players }

    var displayedTurn: DisplayedTurn {
        let showLastClosed: Bool
        switch snapshot.phase {
        case .legWon, .matchWon:
            showLastClosed = true
        case .throwing:
            showLastClosed = awaitingTakeout && snapshot.openTurn == nil
        }
        if showLastClosed, let turn = snapshot.lastClosedTurn {
            return DisplayedTurn(player: turn.playerIndex, darts: turn.darts,
                                 result: snapshot.lastClosedTurnResult, isFinished: true)
        }
        return DisplayedTurn(player: snapshot.currentPlayer, darts: snapshot.openTurn?.darts ?? [],
                             result: snapshot.openTurnResult, isFinished: false)
    }

    /// Finish-Vorschlag für den Spieler am Wurf.
    var checkoutRoute: [Hit]? {
        guard case .throwing(let player, let dartsLeft) = snapshot.phase,
              !displayedTurn.isFinished,
              snapshot.opened.indices.contains(player), snapshot.opened[player]
        else { return nil }
        return CheckoutCalculator.route(for: snapshot.remaining[player], dartsLeft: dartsLeft,
                                        outRule: match.settings.outRule)
    }

    /// Zug, der im Korrektur-Dialog bearbeitet wird.
    var correctableTurn: Turn? {
        snapshot.openTurn ?? snapshot.lastClosedTurn
    }

    // MARK: - Lebenszyklus

    func start() {
        speech.isEnabled = settings.speechEnabled
        UIApplication.shared.isIdleTimerDisabled = true
        guard inputMode == .camera else {
            status = .manual
            speech.say("Game on!")
            return
        }
        camera?.start()
        camera?.setFocusLocked(true)
        motion?.start()
        handledMovements = motion?.movementCount ?? 0
        setStatus(.watching)
        let tuning = settings.detectorTuning
        if let detector {
            Task { await detector.updateTuning(tuning) }
        }
        startLoop()
        speech.say("Game on!")
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        bannerTask?.cancel()
        camera?.setFocusLocked(false)
        camera?.stop()
        motion?.stop()
        speech.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func togglePause() {
        isPaused.toggle()
        guard inputMode == .camera else { return }
        setStatus(isPaused ? .paused : (awaitingTakeout ? .pullDarts : .watching))
    }

    func requestRecalibration() {
        guard inputMode == .camera else { return }
        Task { await recalibrate() }
    }

    // MARK: - Eingaben

    /// Manuell erfasster Dart (Tastenfeld oder Tippen aufs Board).
    func addManualDart(_ hit: Hit, boardPoint: CGPoint? = nil) {
        guard case .throwing = snapshot.phase else { return }
        let dart = DartThrow(hit: hit, source: .manual,
                             boardPoint: boardPoint ?? BoardGeometry.representativePoint(for: hit))
        let outcome = mutate { $0.addDart(dart) }
        react(to: outcome, dart: dart)
    }

    /// Letzten Dart zurücknehmen.
    func undo() {
        let outcome = mutate { $0.undo() }
        switch outcome {
        case .removedDart(let dart):
            if let trackID = trackID(forDart: dart.id) {
                tracker.reject(id: trackID)
                engineDartForTrack[trackID] = nil
            } else if snapshot.openTurn != nil {
                tracker.resumeCollecting()
            }
        case .reopenedTurn:
            tracker.resumeCollecting()
        case .nothing:
            return
        }
        syncTrackerState()
        if inputMode == .camera { setStatus(awaitingTakeout ? .pullDarts : .watching) }
        banner = nil
    }

    /// "Weiter": Zug beenden (fehlende Darts = Miss) bzw. nächstes Leg starten.
    func advance() {
        switch snapshot.phase {
        case .matchWon:
            return
        case .legWon:
            mutate { $0.startNextLeg() }
        case .throwing:
            if snapshot.openTurn != nil || !awaitingTakeout {
                if let result = mutate({ $0.endTurn() }) { announce(result) }
            }
        }
        if inputMode == .camera {
            // Noch steckende Darts beim nächsten Zug nicht mitzählen.
            tracker.startNewTurn(ignoringVisible: true)
            engineDartForTrack.removeAll()
            syncTrackerState()
            setStatus(.watching)
        }
        announceNextPlayer()
    }

    // MARK: - Korrektur

    func previewCorrection(turnID: UUID, entries: [CorrectionEntry]) -> TurnResult? {
        guard let original = match.turn(withID: turnID) else { return nil }
        var copy = match
        copy.replaceDarts(inTurn: turnID, with: makeDarts(from: entries, original: original))
        return copy.result(forTurn: turnID)
    }

    func applyCorrection(turnID: UUID, entries: [CorrectionEntry]) {
        guard let original = match.turn(withID: turnID) else { return }
        let newDarts = makeDarts(from: entries, original: original)

        // Verworfene KI-Darts dürfen nicht erneut gezählt werden.
        for old in original.darts where !newDarts.contains(where: { $0.id == old.id }) {
            if let trackID = trackID(forDart: old.id) {
                tracker.reject(id: trackID)
                engineDartForTrack[trackID] = nil
            }
        }
        if settings.collectTrainingData {
            saveTrainingSample(turnID: turnID, original: original, corrected: newDarts)
        }

        let wasThrowing: Bool
        if case .throwing = snapshot.phase { wasThrowing = true } else { wasThrowing = false }
        mutate { $0.replaceDarts(inTurn: turnID, with: newDarts) }

        if inputMode == .camera {
            if snapshot.openTurn?.id == turnID {
                tracker.resumeCollecting()
            } else if snapshot.openTurn == nil, tracker.phase == .collecting,
                      snapshot.lastClosedTurn?.id == turnID {
                tracker.turnEnded()
            }
            syncTrackerState()
            setStatus(awaitingTakeout ? .pullDarts : .watching)
        }

        switch snapshot.phase {
        case .legWon(let winner) where wasThrowing:
            speech.say("Korrigiert. Game shot! Leg für \(players[winner]).", interrupt: true)
        case .matchWon(let winner) where wasThrowing:
            speech.say("Korrigiert. Game shot and the match! \(players[winner]) gewinnt.", interrupt: true)
        default:
            if let result = match.result(forTurn: turnID), result.isClosed {
                if let bust = result.bust {
                    showBanner(.bust(bust.message))
                    speech.say("Korrigiert. Überworfen.", interrupt: true)
                } else {
                    speech.say("Korrigiert. \(result.scored).", interrupt: true)
                }
            }
        }
    }

    private func makeDarts(from entries: [CorrectionEntry], original: Turn) -> [DartThrow] {
        entries.map { entry in
            if var existing = original.darts.first(where: { $0.id == entry.id }) {
                if existing.hit != entry.hit || (entry.boardPoint != nil && entry.boardPoint != existing.boardPoint) {
                    existing.hit = entry.hit
                    existing.source = existing.source == .camera ? .corrected : .manual
                    existing.isUncertain = false
                    existing.boardPoint = entry.boardPoint ?? BoardGeometry.representativePoint(for: entry.hit)
                }
                return existing
            }
            return DartThrow(hit: entry.hit, source: .manual,
                             boardPoint: entry.boardPoint ?? BoardGeometry.representativePoint(for: entry.hit))
        }
    }

    // MARK: - Erkennungsschleife

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = await self?.step() else { return }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// Ein Analyse-Schritt. Gibt die Wartezeit bis zum nächsten Schritt zurück.
    private func step() async -> TimeInterval {
        guard let detector, let camera else { return 1 }
        if isPaused || snapshot.matchWinner != nil { return 0.3 }

        if let motion {
            if !motion.isStill {
                if status == .watching || status == .pullDarts { setStatus(.holdStill) }
                return 0.25
            }
            if motion.movementCount != handledMovements {
                // Handy wurde bewegt: Kalibrierung prüfen und ggf. automatisch erneuern.
                handledMovements = motion.movementCount
                await verifyCalibration(afterMovement: true)
                return 0.1
            }
            if status == .holdStill { setStatus(awaitingTakeout ? .pullDarts : .watching) }
        }

        guard let frame = camera.engine.latestFrame(), frame.timestamp != lastFrameTimestamp else { return 0.1 }
        lastFrameTimestamp = frame.timestamp
        guard let calibration, calibration.imageSize == frame.size else {
            await recalibrate()
            return 0.2
        }

        isAnalyzing = true
        defer { isAnalyzing = false }
        let started = Date()
        do {
            let candidates = try await detector.detectDarts(in: frame, calibration: calibration)
            var boardVisible: Bool?
            if candidates.isEmpty && (awaitingTakeout || !tracker.darts.isEmpty) {
                // Leeres Bild: Ist das Board frei (Darts gezogen) oder nur verdeckt?
                let board = try await detector.detectBoard(in: frame)
                boardVisible = board.matchingPoints(with: calibration.keypoints,
                                                    tolerance: Self.tolerance(for: calibration)) >= 3
            }
            lastAnalysisMilliseconds = Int(Date().timeIntervalSince(started) * 1000)

            // Manuell ergänzte Darts belegen Plätze im Zug.
            let manualDarts = snapshot.openTurn?.darts.filter { $0.source != .camera }.count ?? 0
            tracker.config.maxDartsPerTurn = max(0, 3 - manualDarts)

            let events = tracker.process(FrameObservation(candidates: candidates, boardVisible: boardVisible,
                                                          timestamp: frame.timestamp))
            handle(events, frame: frame)
            syncTrackerState()
            if case .error = status { setStatus(awaitingTakeout ? .pullDarts : .watching) }

            if detector.cheapBoardCheck, tracker.isEmpty, !awaitingTakeout,
               Date().timeIntervalSince(lastCalibrationCheck) > 20 {
                await verifyCalibration(afterMovement: false)
            }
            // Unbestätigte Kandidaten → schneller erneut hinschauen.
            return tracker.isEmpty ? detector.preferredInterval : min(detector.preferredInterval, 0.15)
        } catch {
            setStatus(.error(error.localizedDescription))
            return 1.5
        }
    }

    private func handle(_ events: [TrackerEvent], frame: AnalysisFrame) {
        for event in events {
            switch event {
            case .dartAdded(let tracked):
                let dart = DartThrow(hit: tracked.hit, source: .camera, confidence: tracked.maxConfidence,
                                     boardPoint: tracked.position, isUncertain: tracked.isUncertain)
                engineDartForTrack[tracked.id] = dart.id
                let outcome = mutate { $0.addDart(dart) }
                if settings.collectTrainingData { rememberFrame(frame) }
                react(to: outcome, dart: dart)

            case .dartRefined(let tracked):
                guard let dartID = engineDartForTrack[tracked.id],
                      snapshot.openTurn?.darts.contains(where: { $0.id == dartID }) == true
                else { continue }
                mutate { $0.updateDart(id: dartID, hit: tracked.hit, boardPoint: tracked.position,
                                       isUncertain: tracked.isUncertain) }

            case .boardCleared:
                if snapshot.openTurn != nil {
                    // Darts gezogen, bevor drei erkannt wurden: der Rest ging daneben.
                    if let result = mutate({ $0.endTurn() }) { announce(result) }
                }
                if case .legWon = snapshot.phase {
                    mutate { $0.startNextLeg() }
                }
                engineDartForTrack.removeAll()
                if snapshot.matchWinner == nil {
                    setStatus(.watching)
                    announceNextPlayer()
                }
            }
        }
    }

    private func react(to outcome: AddDartOutcome, dart: DartThrow) {
        switch outcome {
        case .continued:
            if settings.announceEveryDart { speech.say(dart.hit.spokenText) }
        case .turnComplete(let scored):
            turnFinishedByRules()
            if scored == 180 {
                showBanner(.oneEighty)
                speech.say("Einhundertachtzig!", interrupt: true)
            } else if let result = snapshot.lastClosedTurnResult {
                announce(result)
            }
            if inputMode == .manual { announceNextPlayer() }
        case .bust(let reason):
            turnFinishedByRules()
            showBanner(.bust(reason.message))
            speech.say(reason == .invalidFinish ? "Kein gültiges Finish. Überworfen." : "Überworfen.", interrupt: true)
            if inputMode == .manual { announceNextPlayer() }
        case .legWon(let player):
            turnFinishedByRules()
            speech.say("Game shot! Leg für \(players[player]).", interrupt: true)
        case .matchWon(let player):
            turnFinishedByRules()
            speech.say("Game shot and the match! \(players[player]) gewinnt.", interrupt: true)
        case .rejected:
            break
        }
    }

    private func turnFinishedByRules() {
        guard inputMode == .camera else { return }
        tracker.turnEnded()
        syncTrackerState()
        setStatus(.pullDarts)
    }

    private func announce(_ result: TurnResult) {
        guard !result.isBust, !result.isCheckout else { return }
        if result.scored == 180 {
            speech.say("Einhundertachtzig!")
        } else {
            speech.say("\(result.scored). Rest \(result.endRemaining).")
        }
    }

    private func announceNextPlayer() {
        guard case .throwing(let player, _) = snapshot.phase, snapshot.openTurn == nil,
              snapshot.remaining.indices.contains(player)
        else { return }
        let rest = snapshot.remaining[player]
        if snapshot.opened[player], rest <= 170,
           CheckoutCalculator.route(for: rest, outRule: match.settings.outRule) != nil {
            speech.say("\(players[player]), du brauchst \(rest).")
        } else if players.count > 1 {
            speech.say(players[player])
        }
    }

    // MARK: - Kalibrierung im Spiel

    private func verifyCalibration(afterMovement: Bool) async {
        lastCalibrationCheck = Date()
        guard let detector, let camera, let calibration,
              let frame = camera.engine.latestFrame()
        else { return }
        guard frame.size == calibration.imageSize else {
            await recalibrate()
            return
        }
        guard let detection = try? await detector.detectBoard(in: frame),
              let keypoints = detection.keypoints
        else {
            if afterMovement { setStatus(.error("Board nicht sichtbar – Kamera prüfen")) }
            return
        }
        let tolerance = Self.tolerance(for: calibration)
        let deviation = keypoints.maxDistance(to: calibration.keypoints)
        if deviation > tolerance * 2 {
            await recalibrate()
        } else if deviation <= tolerance {
            // Sanft nachführen: gleicht langsames Absacken des Stativs aus, ohne Rauschen zu übernehmen.
            let blended = BoardKeypoints.blend(calibration.keypoints, keypoints, weight: 0.2)
            if let updated = BoardCalibration(keypoints: blended, imageSize: calibration.imageSize) {
                self.calibration = updated
            }
        }
    }

    /// Neue Kalibrierung aus mehreren Frames (Mittelwert ohne Ausreißer).
    private func recalibrate() async {
        guard let detector, let camera else { return }
        setStatus(.recalibrating)
        let needed = detector.cheapBoardCheck ? 5 : 2
        var samples: [BoardKeypoints] = []
        var sampledSize: CGSize?
        var lastTimestamp: TimeInterval = -1
        var attempts = 0
        while samples.count < needed, attempts < 30, !Task.isCancelled {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(200))
            guard let frame = camera.engine.latestFrame(), frame.timestamp != lastTimestamp else { continue }
            lastTimestamp = frame.timestamp
            if sampledSize != frame.size {
                samples.removeAll()
                sampledSize = frame.size
            }
            if let keypoints = try? await detector.detectBoard(in: frame).keypoints,
               BoardCalibration.problem(with: keypoints, imageSize: frame.size) == nil {
                samples.append(keypoints)
            }
        }
        lastCalibrationCheck = Date()

        guard let size = sampledSize,
              let average = BoardKeypoints.robustAverage(of: samples, tolerance: Self.tolerance(forImageSize: size)),
              average.inliers >= max(1, needed - 2),
              let updated = BoardCalibration(keypoints: average.keypoints, imageSize: size)
        else {
            setStatus(.error("Board nicht gefunden – bitte neu kalibrieren"))
            return
        }
        calibration = updated
        setStatus(awaitingTakeout ? .pullDarts : .watching)
        showBanner(.info("Kalibrierung aktualisiert"))
    }

    static func tolerance(forImageSize size: CGSize) -> CGFloat {
        max(4, hypot(size.width, size.height) * 0.004)
    }

    static func tolerance(for calibration: BoardCalibration) -> CGFloat {
        tolerance(forImageSize: calibration.imageSize)
    }

    // MARK: - Trainingsdaten

    private func rememberFrame(_ frame: AnalysisFrame) {
        guard let turnID = snapshot.openTurn?.id ?? snapshot.lastClosedTurn?.id else { return }
        Task { [weak self] in
            let encoded = await Task.detached(priority: .utility) {
                try? FrameRenderer.shared.jpeg(from: frame.pixelBuffer, maxDimension: 2560, quality: 0.9)
            }.value
            if let encoded { self?.turnFrames[turnID] = (encoded.data, encoded.size) }
        }
    }

    private func saveTrainingSample(turnID: UUID, original: Turn, corrected: [DartThrow]) {
        guard let calibration, let frame = turnFrames[turnID] else { return }
        let sx = frame.size.width / calibration.imageSize.width
        let sy = frame.size.height / calibration.imageSize.height

        func record(_ dart: DartThrow) -> TrainingDataRecorder.DartRecord {
            var imagePoint: CGPoint?
            if let boardPoint = dart.boardPoint, let p = calibration.imagePoint(fromBoard: boardPoint) {
                imagePoint = CGPoint(x: p.x * sx, y: p.y * sy)
            }
            return TrainingDataRecorder.DartRecord(label: dart.hit.label, points: dart.hit.points,
                                                   source: dart.source.rawValue, confidence: dart.confidence,
                                                   boardPoint: dart.boardPoint, imagePoint: imagePoint)
        }

        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let sample = TrainingDataRecorder.Sample(
            createdAt: Date(),
            imageFile: "dartvision_\(stamp).jpg",
            imageSize: frame.size,
            keypoints: calibration.keypoints.scaled(x: sx, y: sy),
            detected: original.darts.map(record),
            corrected: corrected.map(record)
        )
        let data = frame.data
        Task.detached(priority: .utility) {
            TrainingDataRecorder.save(jpeg: data, sample: sample)
        }
    }

    // MARK: - Hilfsfunktionen

    @discardableResult
    private func mutate<T>(_ change: (inout X01Match) -> T) -> T {
        let result = change(&match)
        snapshot = match.snapshot()
        onMatchChange?(match)
        return result
    }

    private func trackID(forDart dartID: UUID) -> UUID? {
        engineDartForTrack.first(where: { $0.value == dartID })?.key
    }

    private func syncTrackerState() {
        if liveDarts != tracker.darts { liveDarts = tracker.darts }
        let waiting = tracker.phase == .waitingForTakeout
        if awaitingTakeout != waiting { awaitingTakeout = waiting }
    }

    private func setStatus(_ newStatus: Status) {
        if status != newStatus { status = newStatus }
    }

    private func showBanner(_ newBanner: Banner) {
        banner = newBanner
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }
}
