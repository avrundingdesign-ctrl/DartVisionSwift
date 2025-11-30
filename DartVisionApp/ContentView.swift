import SwiftUI
import AVFoundation
import Foundation

enum GameState { case idle, ready, active }

struct ContentView: View {
    @StateObject private var cameraModel = CameraModel()
    @State private var liveScores: [Int] = []
    @State private var gameState: GameState = .idle
    @State private var selectedGame: Int? = 301           // ✅ Standard 301
    @State private var remaining: Int = 0
    @State private var isPaused: Bool = false
    
    let dartTracker = DartTracker()
    
    // DartVisionUI-States
    @State private var players: [String] = []
    @State private var remainingScores: [Int] = []
    @State private var currentPlayerIndex = 0
    @State private var doubleOut: Bool = false
    @State private var showWinOverlay = false
    @State private var winnerName: String?
    
    var body: some View {
        ZStack{
            DartVisionUI(
                gameState: $gameState,
                selectedGame: $selectedGame,
                remaining: $remaining,
                isPaused: $isPaused,
                players: $players,
                doubleOut: $doubleOut,
                currentPlayerIndex: $currentPlayerIndex,
                remainingScores: $remainingScores,
                currentScores: liveScores,
                startAction: startGame,
                stopAction: stopGame,
                pauseAction: togglePause,
                uploadHandler: cameraModel.uploadImageToServer,
                // ⬇️ correctionAction MUSS vor cameraModel kommen
                correctionAction: { /* TODO: Funktion kommt später */ },
                cameraModel: cameraModel
            )
            if showWinOverlay, let winner = winnerName {
                        WinOverlayView(winnerName: winner) {
                            // Diese Aktion wird erst ausgeführt, wenn der User den Button drückt
                            finishGame()
                        }
                        .zIndex(10) // Ganz nach oben legen
                        .transition(.opacity) // Schickes Einblenden
                    }
            
        }
        .onAppear {
            cameraModel.configure()
            
            cameraModel.dartTracker.onScoresUpdated = { newScores in
                DispatchQueue.main.async {
                    self.liveScores = newScores
                }
            }
            // Beobachte Ereignis "Zug beendet"
            NotificationCenter.default.addObserver(forName: .didFinishTurn, object: nil, queue: .main) { notif in
                if let total = notif.object as? Int {
                    handleTurnFinished(with: total)
                }
            }
            NotificationCenter.default.addObserver(forName: .Throw, object: nil, queue: .main) { notif in
                if let score = notif.object as? Int {
                    thrown(with: score)
                }
            }

        }
        
    }
    private func thrown(with Score: Int) {
        guard !players.isEmpty else { return }

        let currentIndex = currentPlayerIndex
        let playerName = players[currentIndex]
        
        // Aktuellen Rest des Spielers holen
        let currentRest = remainingScores[currentIndex]
        
        // 1. Neuen Rest berechnen (provisorisch)
        let newRest = currentRest - Score
        
        if newRest < 0 {
            // --- FALL 1: ÜBERWORFEN (Bust) ---
            print("❌ Überworfen! Score bleibt bei \(currentRest).")
            
            let bustUtterance = AVSpeechUtterance(string: "Überworfen")
            bustUtterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
            cameraModel.synthesizer.speak(bustUtterance)
            
            // Score NICHT aktualisieren (wir behalten currentRest)
            // Direkt zum nächsten Spieler
            currentPlayerIndex = (currentPlayerIndex + 1) % players.count
            
        } else if newRest == 0 {
            let playerName = players[currentPlayerIndex]
            
            // 1. Score auf 0 setzen
            remainingScores[currentPlayerIndex] = 0
            remaining = 0
            
            
            // 3. Aufnahme stoppen und Overlay zeigen
            cameraModel.isGameActive = false
            cameraModel.stopCapturing()
            
            self.winnerName = playerName
            withAnimation(.spring()) {
                self.showWinOverlay = true
            }
            
        } else {
            // --- FALL 3: NORMAL WEITER (Rest > 0) ---
            
            // Score aktualisieren
            remainingScores[currentIndex] = newRest
            remaining = newRest
                        
        }
    }
    // MARK: - Spielzug-Logik
    private func handleTurnFinished(with totalScore: Int) {
        guard !players.isEmpty else { return }

        let currentIndex = currentPlayerIndex
        let playerName = players[currentIndex]
        
        // Aktuellen Rest des Spielers holen
        let currentRest = remainingScores[currentIndex]
        
        // 1. Neuen Rest berechnen (provisorisch)
        let newRest = currentRest - totalScore
        
        print("💥 \(playerName) wirft \(totalScore). Alter Rest: \(currentRest) -> Neu: \(newRest)")

        // Laufende Sprachausgabe stoppen
        cameraModel.synthesizer.stopSpeaking(at: .immediate)

        // 2. Die 3 Fälle behandeln
        if newRest < 0 {
            // --- FALL 1: ÜBERWORFEN (Bust) ---
            print("❌ Überworfen! Score bleibt bei \(currentRest).")
            
            let bustUtterance = AVSpeechUtterance(string: "Überworfen")
            bustUtterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
            cameraModel.synthesizer.speak(bustUtterance)
            
            // Score NICHT aktualisieren (wir behalten currentRest)
            // Direkt zum nächsten Spieler
            currentPlayerIndex = (currentPlayerIndex + 1) % players.count
            
        } else if newRest == 0 {
            let playerName = players[currentPlayerIndex]
            
            // 1. Score auf 0 setzen
            remainingScores[currentPlayerIndex] = 0
            remaining = 0
            
            
            // 3. Aufnahme stoppen und Overlay zeigen
            cameraModel.isGameActive = false
            cameraModel.stopCapturing()
            
            self.winnerName = playerName
            withAnimation(.spring()) {
                self.showWinOverlay = true
            }
            
        } else {
            // --- FALL 3: NORMAL WEITER (Rest > 0) ---
            print("✅ Gültiger Wurf. Rest: \(newRest)")
            
            // Score aktualisieren
            remainingScores[currentIndex] = newRest
            remaining = newRest
            
            let restUtterance = AVSpeechUtterance(string: "Rest \(newRest)")
            restUtterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
            restUtterance.rate = 0.45
            cameraModel.synthesizer.speak(restUtterance)
            
            // Nächster Spieler
            currentPlayerIndex = (currentPlayerIndex + 1) % players.count
        }
    }
    private func finishGame() {
        cameraModel.isGameActive = false
        cameraModel.stopCapturing()
        cameraModel.currentGame.keypoints = nil
        cameraModel.dartTracker.reset() // Tracker Reset
        self.liveScores = []
        gameState = .ready
        
        // Popup schließen
        self.showWinOverlay = false
        self.winnerName = nil
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

