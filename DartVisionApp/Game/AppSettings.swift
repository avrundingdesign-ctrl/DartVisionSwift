import Foundation
import Observation

nonisolated enum InputMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case camera
    case manual

    var id: String { rawValue }
}

/// Persistente Einstellungen (UserDefaults, JSON). Jede Änderung wird sofort gespeichert.
@Observable
final class AppSettings {

    nonisolated struct Values: Codable, Equatable, Sendable {
        var players: [String] = ["Spieler 1", "Spieler 2"]
        var x01 = X01Settings()
        var inputMode: InputMode = .camera
        var backend: DetectionBackend = .onDevice
        var serverURL = "https://chris-hesse.com/upload"
        var speechEnabled = true
        var announceEveryDart = false
        /// Mindest-Konfidenz, ab der ein erkannter Dart gezählt wird.
        var minConfidence = 0.35
        /// Maximaler Board-Zoom für die Dart-Erkennung auf dem Gerät (1 = aus, experimentell).
        var maxBoardZoom = 1.0
        /// Bei Korrekturen Bild + Labels für späteres Nachtrainieren speichern.
        var collectTrainingData = false
    }

    private var values: Values

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "dartvision.settings.v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded = Values()
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(Values.self, from: data) {
            loaded = decoded
        }
        if !OnDeviceDetector.modelsAvailable { loaded.backend = .server }
        values = loaded
    }

    var players: [String] {
        get { values.players }
        set { update { $0.players = newValue } }
    }
    var x01: X01Settings {
        get { values.x01 }
        set { update { $0.x01 = newValue } }
    }
    var inputMode: InputMode {
        get { values.inputMode }
        set { update { $0.inputMode = newValue } }
    }
    var backend: DetectionBackend {
        get { values.backend }
        set { update { $0.backend = newValue } }
    }
    var serverURL: String {
        get { values.serverURL }
        set { update { $0.serverURL = newValue } }
    }
    var speechEnabled: Bool {
        get { values.speechEnabled }
        set { update { $0.speechEnabled = newValue } }
    }
    var announceEveryDart: Bool {
        get { values.announceEveryDart }
        set { update { $0.announceEveryDart = newValue } }
    }
    var minConfidence: Double {
        get { values.minConfidence }
        set { update { $0.minConfidence = newValue } }
    }
    var maxBoardZoom: Double {
        get { values.maxBoardZoom }
        set { update { $0.maxBoardZoom = newValue } }
    }
    var collectTrainingData: Bool {
        get { values.collectTrainingData }
        set { update { $0.collectTrainingData = newValue } }
    }

    var detectorTuning: DetectorTuning {
        DetectorTuning(minConfidence: 0.2, maxBoardZoom: values.maxBoardZoom)
    }

    private func update(_ change: (inout Values) -> Void) {
        var copy = values
        change(&copy)
        guard copy != values else { return }
        values = copy
        if let data = try? JSONEncoder().encode(copy) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
