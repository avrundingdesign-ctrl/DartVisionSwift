import SwiftUI
import AVFoundation
import Foundation

enum GameState { case idle, ready, active }

struct TurnSnapshot {
    let playerIndex: Int
    let scoreThrown: Int
    let previousRest: Int
}
struct ContentView: View {
    @StateObject private var cameraModel = CameraModel()
    @State private var liveScores: [Int] = []
    @State private var gameState: GameState = .idle
    @State private var selectedGame: Int? = 301           // ✅ Standard 301
    @State private var remaining: Int = 0
    @State private var isPaused: Bool = false
    let dartTracker = DartTracker()
    @State private var lastTurn: TurnSnapshot?
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
                correctionAction: correctLastTurn,
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
                if let totalDart = notif.object as? DartData {
                    handleTurnFinished(with: totalDart)
                }
            }
            NotificationCenter.default.addObserver(forName: .Throw, object: nil, queue: .main) { notif in
                if let currentDart = notif.object as? DartData {
                    thrown(with: currentDart)
                }
            }

        }
        
    }
    private func thrown(with currentDart: DartData) {
        guard !players.isEmpty else { return }

        let currentIndex = currentPlayerIndex
        let playerName = players[currentIndex]
        
        // Aktuellen Rest des Spielers holen
        let currentRest = remainingScores[currentIndex]
        lastTurn = TurnSnapshot(playerIndex: currentIndex, scoreThrown: currentDart.score, previousRest: currentRest)
        // 1. Neuen Rest berechnen (provisorisch)
        let newRest = currentRest - currentDart.score
        
        // Laufende Sprachausgabe stoppen
        cameraModel.synthesizer.stopSpeaking(at: .immediate)
        
        if newRest < 0 {
            // --- FALL 1: ÜBERWORFEN (Bust) ---
            print("❌ Überworfen! Score bleibt bei \(currentRest).")
            cameraModel.isThrowBusted = true
            
            let bustUtterance = AVSpeechUtterance(string: "Überworfen")
            bustUtterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
            cameraModel.synthesizer.speak(bustUtterance)
            
            // Score NICHT aktualisieren (wir behalten currentRest)
            // Direkt zum nächsten Spieler wird NICHT hier gemacht (erst nach 3 Darts)
        }
        else if newRest == 0 && doubleOut {
            let fieldtype = currentDart.field_type
            if fieldtype == "double" {
                remainingScores[currentPlayerIndex] = 0
                remaining = 0
                cameraModel.isThrowBusted = false
                
                // 3. Aufnahme stoppen und Overlay zeigen
                cameraModel.isGameActive = false
                cameraModel.stopCapturing()
                
                self.winnerName = playerName
                withAnimation(.spring()) {
                    self.showWinOverlay = true
                }
            }
            else {
                // Nicht mit Double ausgecheckt -> Bust
                print("❌ Double-Out erforderlich! Score bleibt bei \(currentRest).")
                cameraModel.isThrowBusted = true
                
                let checkfieldtype = AVSpeechUtterance(string: "Double erforderlich")
                checkfieldtype.voice = AVSpeechSynthesisVoice(language: "de-DE")
                cameraModel.synthesizer.speak(checkfieldtype)
            }
        } else if newRest == 0 && !doubleOut {
            // 1. Score auf 0 setzen
            remainingScores[currentPlayerIndex] = 0
            remaining = 0
            cameraModel.isThrowBusted = false
            
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
            cameraModel.isThrowBusted = false
        }
    }
    // MARK: - Spielzug-Logik
    private func handleTurnFinished(with totalDart: DartData) {
        guard !players.isEmpty else { return }

        let currentIndex = currentPlayerIndex
        let playerName = players[currentIndex]
        
        // Aktuellen Rest des Spielers holen
        let currentRest = remainingScores[currentIndex]
        lastTurn = TurnSnapshot(playerIndex: currentIndex, scoreThrown: totalDart.score, previousRest: currentRest)
        // 1. Neuen Rest berechnen (provisorisch)
        let newRest = currentRest - totalDart.score
        
        // Laufende Sprachausgabe stoppen
        cameraModel.synthesizer.stopSpeaking(at: .immediate)

        // 2. Die 3 Fälle behandeln
        if newRest < 0 {
            // --- FALL 1: ÜBERWORFEN (Bust) ---
            print("❌ Überworfen! Score bleibt bei \(currentRest).")
            cameraModel.isThrowBusted = true
            let bustUtterance = AVSpeechUtterance(string: "Überworfen")
            bustUtterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
            cameraModel.synthesizer.speak(bustUtterance)
            
            // Score NICHT aktualisieren (wir behalten currentRest)
            // Direkt zum nächsten Spieler
            currentPlayerIndex = (currentPlayerIndex + 1) % players.count
            
        }
        else if newRest == 0 && doubleOut {
            let fieldtype = totalDart.field_type
            if fieldtype == "double" {
                remainingScores[currentPlayerIndex] = 0
                remaining = 0
                cameraModel.isThrowBusted = false
                
                // 3. Aufnahme stoppen und Overlay zeigen
                cameraModel.isGameActive = false
                cameraModel.stopCapturing()
                
                self.winnerName = playerName
                withAnimation(.spring()) {
                    self.showWinOverlay = true
                }
            }
            else {
                // Nicht mit Double ausgecheckt -> Bust
                print("❌ Double-Out erforderlich! Score bleibt bei \(currentRest).")
                cameraModel.isThrowBusted = true
                
                let checkfieldtype = AVSpeechUtterance(string: "Double erforderlich")
                checkfieldtype.voice = AVSpeechSynthesisVoice(language: "de-DE")
                cameraModel.synthesizer.speak(checkfieldtype)
                
                // Score NICHT ändern, zum nächsten Spieler
                currentPlayerIndex = (currentPlayerIndex + 1) % players.count
            }
        }
        else if newRest == 0 && !doubleOut {
            let playerName = players[currentPlayerIndex]
            
            // 1. Score auf 0 setzen
            remainingScores[currentPlayerIndex] = 0
            remaining = 0
            
            cameraModel.isThrowBusted = false
            // 3. Aufnahme stoppen und Overlay zeigen
            cameraModel.isGameActive = false
            cameraModel.stopCapturing()
            
            self.winnerName = playerName
            withAnimation(.spring()) {
                self.showWinOverlay = true
            }
            
        }
        
        
        
        
        
        
        
        
        else {
            // --- FALL 3: NORMAL WEITER (Rest > 0) ---
            print("✅ Gültiger Wurf. Rest: \(newRest)")
            cameraModel.isThrowBusted = false
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
    private func correctLastTurn(newTotal: Int) {
        guard let last = lastTurn else { return }
        
        print("🔧 Korrektur für \(players[last.playerIndex]): Alt \(last.scoreThrown) -> Neu \(newTotal)")
        
        // Wir rechnen vom "previousRest" aus (dem Stand VOR dem falschen Wurf)
        let oldRest = last.previousRest
        let correctedNewRest = oldRest - newTotal
        
        // Jetzt wenden wir die Dart-Regeln neu an
        if correctedNewRest < 0 {
            // Bust (Überworfen) durch Korrektur
            remainingScores[last.playerIndex] = oldRest // Score zurücksetzen
            cameraModel.isThrowBusted = true
            // Optional: Ton abspielen "Überworfen"
        } else if correctedNewRest == 0 {
            // Sieg durch Korrektur
            remainingScores[last.playerIndex] = 0
            remaining = 0
            cameraModel.isThrowBusted = false
            winnerName = players[last.playerIndex]
            showWinOverlay = true
            cameraModel.stopCapturing()
        } else {
            // Gültiger Score
            remainingScores[last.playerIndex] = correctedNewRest
            cameraModel.isThrowBusted = false
            // Falls der Spieler zufällig gerade dran ist, update auch 'remaining'
            if currentPlayerIndex == last.playerIndex {
                remaining = correctedNewRest
            }
        }
        
        // Snapshot updaten (falls man sich noch mal korrigiert)
        lastTurn = TurnSnapshot(playerIndex: last.playerIndex, scoreThrown: newTotal, previousRest: oldRest)
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

