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
        let startingRemaining = remainingScores.indices.contains(currentIndex) ? remainingScores[currentIndex] : (selectedGame ?? 0)
        let proposedRemaining = startingRemaining - totalScore

        print("💥 \(playerName) wirft \(totalScore) Punkte!")

        // 🧮 Überworfen erkennen (Double Out wird bewusst ignoriert)
        if proposedRemaining < 0 {
            speak("Überworfen")
            remaining = startingRemaining
        } else {
            if remainingScores.indices.contains(currentIndex) {
                remainingScores[currentIndex] = max(proposedRemaining, 0)
            }

            let rest = remainingScores[currentIndex]
            remaining = rest

            speak("Rest \(rest)")

            // 🏁 Siegbedingung
            if rest == 0 {
                cameraModel.synthesizer.stopSpeaking(at: .immediate)
                let win = AVSpeechUtterance(string: "\(playerName) hat gewonnen!")
                win.voice = AVSpeechSynthesisVoice(language: "de-DE")
                cameraModel.synthesizer.speak(win)

                cameraModel.isGameActive = false
                cameraModel.stopCapturing()
                cameraModel.currentGame.keypoints = nil
                cameraModel.resetTurnState()
                gameState = .ready
                return
            }
        }

        advanceToNextPlayer()
    }

    // MARK: - Game Controls
    private func startGame() {
        cameraModel.isGameActive = true
        guard let start = selectedGame else { return }
        isPaused = false
        gameState = .active

        // 🧹 Board- und Dart-Daten leeren + Spielerstart
        cameraModel.currentGame = GameData()
        cameraModel.resetTurnState()
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
        cameraModel.resetTurnState()
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

    private func advanceToNextPlayer() {
        guard !players.isEmpty else { return }
        currentPlayerIndex = (currentPlayerIndex + 1) % players.count
        print("➡️ Nächster Spieler: \(players[currentPlayerIndex])")

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if let handler = self.cameraModel.photoHandler {
                print("🔁 Nächster Spieler – starte neue Aufnahme.")
                self.cameraModel.stopCapturing()
                self.cameraModel.startCapturing(photoHandler: handler)
            }
        }
    }

    private func speak(_ text: String) {
        cameraModel.synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        utterance.rate = 0.45
        cameraModel.synthesizer.speak(utterance)
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
