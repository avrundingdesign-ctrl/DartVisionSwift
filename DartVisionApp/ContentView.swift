import SwiftUI
import AVFoundation
import Foundation

enum GameState { case idle, ready, active }

struct ContentView: View {
    @StateObject private var cameraModel = CameraModel()
    @State private var gameState: GameState = .idle
    @State private var selectedGame: Int? = 301           // ✅ Standard 301
    @State private var remaining: Int = 0
    @State private var isPaused: Bool = false


    // DartVisionUI-States
    @State private var players: [String] = []
    @State private var remainingScores: [Int] = []
    @State private var currentPlayerIndex = 0
    @State private var doubleOut: Bool = false

    var body: some View {
        DartVisionUI(
            gameState: $gameState,
            selectedGame: $selectedGame,
            remaining: $remaining,
            isPaused: $isPaused,
            players: $players,
            doubleOut: $doubleOut,
            currentPlayerIndex: $currentPlayerIndex,
            remainingScores: $remainingScores,
            startAction: startGame,
            stopAction: stopGame,
            pauseAction: togglePause,
            uploadHandler: cameraModel.uploadImageToServer,
            // ⬇️ correctionAction MUSS vor cameraModel kommen
            correctionAction: { /* TODO: Funktion kommt später */ },
            cameraModel: cameraModel
        )

        .onAppear {
            cameraModel.configure()

            // Beobachte Ereignis "Zug beendet"
            NotificationCenter.default.addObserver(forName: .didFinishTurn, object: nil, queue: .main) { notif in
                if let total = notif.object as? Int {
                    handleTurnFinished(with: total)
                }
            }
        }
    }

    // MARK: - Spielzug-Logik
    private func handleTurnFinished(with totalScore: Int) {
        guard !players.isEmpty else { return }

        let currentIndex = currentPlayerIndex
        let playerName = players[currentIndex]

        print("💥 \(playerName) wirft \(totalScore) Punkte!")

        // 🔹 Bust-Prüfung: Wenn neuer Score > Rest Score → Überworfen
        guard remainingScores.indices.contains(currentIndex) else { return }
        let currentRemaining = remainingScores[currentIndex]
        
        if totalScore > currentRemaining {
            print("❌ Überworfen! \(totalScore) > \(currentRemaining)")
            cameraModel.synthesizer.stopSpeaking(at: .immediate)
            let bustUtterance = AVSpeechUtterance(string: "Überworfen! Nächster Spieler.")
            bustUtterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
            bustUtterance.rate = 0.45
            cameraModel.synthesizer.speak(bustUtterance)
            
            // Nächster Spieler (ohne Score-Änderung)
            nextPlayer()
            return
        }

        // 🔹 Restscore für den aktuellen Spieler aktualisieren
        let newRemaining = currentRemaining - totalScore
        remainingScores[currentIndex] = newRemaining
        remaining = newRemaining

        // 🏁 Siegbedingung
        if newRemaining == 0 {
            // 🔹 Double-Out-Prüfung
            if doubleOut {
                // TODO: Prüfen ob letzter Wurf ein Double war
                // Aktuell wird nur geprüft ob Score == 0, nicht ob es ein Double war
                // Für vollständige Implementierung müsste der letzte Dart-Score mitgesendet werden
                print("⚠️ Double-Out aktiv, aber keine Prüfung ob letzter Wurf Double war")
            }
            
            cameraModel.synthesizer.stopSpeaking(at: .immediate)
            let win = AVSpeechUtterance(string: "\(playerName) hat gewonnen!")
            win.voice = AVSpeechSynthesisVoice(language: "de-DE")
            cameraModel.synthesizer.speak(win)

            // Spielstatus sofort deaktivieren (Observer feuert dann auch nicht mehr)
            cameraModel.isGameActive = false

            // Aufnahme stoppen
            cameraModel.stopCapturing()

            // 🔹 WICHTIG: Board- und Dart-Daten leeren
            cameraModel.currentGame.keypoints = nil
            cameraModel.currentGame.detectedDarts.removeAll()
            cameraModel.currentGame.dartScores.removeAll()
            cameraModel.clearLastDartPositions()

            // UI zurück
            gameState = .ready
            return
        }

        // 🔊 Sprachansage Restpunkte (Race vermeiden)
        cameraModel.synthesizer.stopSpeaking(at: .immediate)
        let restUtterance = AVSpeechUtterance(string: "Rest \(newRemaining)")
        restUtterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        restUtterance.rate = 0.45
        cameraModel.synthesizer.speak(restUtterance)

        // 🔄 Nächster Spieler
        nextPlayer()
    }
    
    // MARK: - Spielerwechsel
    private func nextPlayer() {
        // 🔹 WICHTIG: lastDartPositions beim Spielerwechsel leeren
        cameraModel.clearLastDartPositions()
        
        // Spieler wechseln
        currentPlayerIndex = (currentPlayerIndex + 1) % players.count
        print("➡️ Nächster Spieler: \(players[currentPlayerIndex])")

        // Pipeline neu starten nach 4 Sekunden
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if let handler = self.cameraModel.photoHandler {
                print("🔁 Nächster Spieler – starte neue Aufnahme.")
                self.cameraModel.stopCapturing()
                self.cameraModel.startCapturing(photoHandler: handler)
            }
        }
    }

    // MARK: - Game Controls
    private func startGame() {
        cameraModel.isGameActive = true
        guard let start = selectedGame else { return }
        isPaused = false
        gameState = .active

        // 🧹 Board- und Dart-Daten leeren + Spielerstart
        cameraModel.currentGame = GameData()
        currentPlayerIndex = 0

        if players.isEmpty {
            players = ["Player 1"]
        }

        // 🔹 Pro-Spieler Restscore initialisieren
        remainingScores = Array(repeating: start, count: players.count)
        remaining = start

        // Kamera starten
        cameraModel.startCapturing { cameraModel.uploadImageToServer($0) }

        print("🎯 Spiel gestartet mit \(players.count) Spieler(n)")
    }

    private func stopGame() {
        cameraModel.isGameActive = false
        cameraModel.stopCapturing()
        gameState = .ready
    }

    private func togglePause() {
        if isPaused {
            isPaused = false
            cameraModel.isGameActive = true
            cameraModel.startCapturing { cameraModel.uploadImageToServer($0) }
        } else {
            isPaused = true
            cameraModel.isGameActive = false
            cameraModel.stopCapturing()
        }
    }
}

// Optional: Server-Reset-Helfer (unverändert)
private func resetServerState() {
    guard let url = URL(string: "https://api.chris-hesse.com/upload") else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    let body = "reset=true".data(using: .utf8)
    request.httpBody = body
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    URLSession.shared.dataTask(with: request) { data, _, _ in
        if let data = data,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = json["status"] as? String {
            print("🔁 Server Reset:", status)
        }
    }.resume()
}
