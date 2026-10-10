import Foundation
import Observation

/// App-weiter Zustand: Navigation, Einstellungen, Kamera, KI und das laufende Spiel.
@Observable
final class AppModel {

    enum Route: Equatable {
        case home
        case calibration
        case game
        case results
    }

    var route: Route = .home
    let settings = AppSettings()
    let camera = CameraController()
    let motion = MotionMonitor()
    let speech = SpeechCaller()

    private(set) var session: GameSession?
    private(set) var detectorError: String?
    private(set) var savedMatch: X01Match?

    /// Kalibrierung der letzten Kamera-Runde (für "Revanche" ohne neues Kalibrieren).
    @ObservationIgnored private var lastCalibration: BoardCalibration?
    @ObservationIgnored private var detector: (any DartDetector)?
    @ObservationIgnored private var detectorKey: String?
    @ObservationIgnored private let savedMatchKey = "dartvision.savedMatch.v2"
    @ObservationIgnored private var resumeMatch: X01Match?

    init() {
        if let data = UserDefaults.standard.data(forKey: savedMatchKey),
           let match = try? JSONDecoder().decode(X01Match.self, from: data),
           match.snapshot().matchWinner == nil {
            savedMatch = match
        }
    }

    // MARK: - KI

    /// Liefert die KI passend zu den Einstellungen (wird nur bei Änderungen neu erzeugt).
    func makeDetector() async -> (any DartDetector)? {
        detectorError = nil
        switch settings.backend {
        case .onDevice:
            if detectorKey == "onDevice", let detector { return detector }
            do {
                let created = try await Task.detached(priority: .userInitiated) {
                    try OnDeviceDetector()
                }.value
                await created.updateTuning(settings.detectorTuning)
                detector = created
                detectorKey = "onDevice"
                return created
            } catch {
                detectorError = error.localizedDescription
                return nil
            }
        case .server:
            guard let url = URL(string: settings.serverURL.trimmingCharacters(in: .whitespaces)),
                  url.scheme?.hasPrefix("http") == true
            else {
                detectorError = "Ungültige Server-Adresse."
                return nil
            }
            let key = "server:\(url.absoluteString)"
            if detectorKey == key, let detector { return detector }
            let created = ServerDetector(endpoint: url)
            await created.updateTuning(settings.detectorTuning)
            detector = created
            detectorKey = key
            return created
        }
    }

    // MARK: - Spielablauf

    /// Startknopf auf dem Home-Screen.
    func beginNewGame() {
        resumeMatch = nil
        clearSavedMatch()
        if settings.inputMode == .camera {
            route = .calibration
        } else {
            startSession(match: newMatch(), calibration: nil)
        }
    }

    /// Gespeichertes Spiel fortsetzen.
    func resumeSavedGame() {
        guard let savedMatch else { return }
        resumeMatch = savedMatch
        if settings.inputMode == .camera {
            route = .calibration
        } else {
            startSession(match: savedMatch, calibration: nil)
        }
    }

    /// Von der Kalibrieransicht aufgerufen.
    func calibrationFinished(_ calibration: BoardCalibration) {
        lastCalibration = calibration
        let match = resumeMatch ?? newMatch()
        resumeMatch = nil
        startSession(match: match, calibration: calibration)
    }

    func rematch() {
        guard let previous = session?.match else { return }
        let match = X01Match(settings: previous.settings, players: previous.players)
        let calibration = session?.calibration ?? lastCalibration
        if session?.inputMode == .camera, calibration == nil {
            endSession()
            route = .calibration
            return
        }
        startSession(match: match, calibration: session?.inputMode == .camera ? calibration : nil)
    }

    func showResults() {
        session?.stop()
        route = .results
    }

    func endSession() {
        if let match = session?.match { lastCalibration = session?.calibration ?? lastCalibration; persist(match) }
        session?.stop()
        session = nil
        camera.stop()
        motion.stop()
        route = .home
    }

    func cancelCalibration() {
        camera.stop()
        motion.stop()
        resumeMatch = nil
        route = .home
    }

    func discardSavedMatch() {
        clearSavedMatch()
    }

    private func newMatch() -> X01Match {
        let names = settings.players
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return X01Match(settings: settings.x01, players: names)
    }

    private func startSession(match: X01Match, calibration: BoardCalibration?) {
        session?.stop()
        let usesCamera = calibration != nil
        let newSession = GameSession(
            match: match,
            inputMode: usesCamera ? .camera : .manual,
            calibration: calibration,
            detector: usesCamera ? detector : nil,
            camera: usesCamera ? camera : nil,
            motion: usesCamera ? motion : nil,
            speech: speech,
            settings: settings
        )
        newSession.onMatchChange = { [weak self] match in
            self?.persist(match)
        }
        session = newSession
        route = .game
        newSession.start()
    }

    // MARK: - Speichern zum Fortsetzen

    private func persist(_ match: X01Match) {
        if match.snapshot().matchWinner != nil {
            clearSavedMatch()
            return
        }
        if let data = try? JSONEncoder().encode(match) {
            UserDefaults.standard.set(data, forKey: savedMatchKey)
        }
        savedMatch = match
    }

    private func clearSavedMatch() {
        UserDefaults.standard.removeObject(forKey: savedMatchKey)
        savedMatch = nil
    }
}
