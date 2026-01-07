import SwiftUI
import AVFoundation

struct Player: Identifiable {
    let id = UUID()
    var name: String
    var remaining: Int
}

struct AnalogView: View {
    @State private var selectedGame: Int? = nil
    @State private var players: [Player] = []
    @State private var currentPlayerIndex: Int = 0
    @State private var multiplier: Int = 1
    @State private var gameStarted = false
    @State private var newPlayer1 = ""
    @State private var newPlayer2 = ""
    @State private var dartsThrown = 0
    @State private var doubleOut = false
    @State private var showWinAlert = false
    @State private var winnerName = ""

    private let synthesizer = AVSpeechSynthesizer()

    var body: some View {
        VStack(spacing: 25) {
            if !gameStarted {
                // ---------- Menü ----------
                Text("Play Analog")
                    .font(.custom("Italiana-Regular", size: 42))
                    .foregroundColor(.dvInk)
                    .padding(.top, 40)

                VStack(spacing: 25) {
                    // Spielmodus
                    HStack(spacing: 20) {
                        modeButton("301", 301)
                        modeButton("501", 501)
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 10)

                    // Spieler
                    VStack(spacing: 20) {
                        stylishTextField("Spieler 1", text: $newPlayer1)
                        stylishTextField("Spieler 2", text: $newPlayer2)
                    }
                    .padding(.horizontal, 40)

                    // Double-Out-Toggle
                    Toggle(isOn: $doubleOut) {
                        Text("Double Out")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.dvInk)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .dvPrimary))
                    .padding(.horizontal, 40)

                    // Play
                    Button(action: startGame) {
                        Text("Play")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedGame != nil ? Color.dvPrimary : Color.dvGray)
                            )
                            .padding(.horizontal, 40)
                    }
                    .disabled(selectedGame == nil || newPlayer1.isEmpty || newPlayer2.isEmpty)
                }
            } else {
                // ---------- SPIEL ----------
                VStack(spacing: 20) {
                    Text("Am Zug: \(players[currentPlayerIndex].name)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.dvInk)

                    // Restpunkte
                    HStack(spacing: 20) {
                        ForEach(players.indices, id: \.self) { i in
                            VStack(spacing: 8) {
                                Text(players[i].name)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.dvInk)
                                Text("\(players[i].remaining)")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(
                                        i == currentPlayerIndex ? .dvPrimary : .dvGray
                                    )
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    // Multiplikatoren
                    HStack(spacing: 25) {
                        multButton("D", 2, color: .dvAccentRed)
                        multButton("T", 3, color: .dvPrimary)
                    }
                    .padding(.top, 5)

                    // Zahlen 1–20
                    LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 5), spacing: 15) {
                        ForEach(1...20, id: \.self) { num in
                            Button { addScore(num) } label: {
                                Text("\(num)")
                                    .font(.system(size: 22, weight: .semibold))
                                    .frame(width: 60, height: 60)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.dvMode)
                                    )
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    // Bulls
                    HStack(spacing: 30) {
                        bullButton("25", value: 25)
                        bullButton("50", value: 50)
                    }
                    .padding(.top, 10)

                    // Stop
                    Button(action: resetGame) {
                        Text("Stop")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.dvAccentRed)
                            )
                            .padding(.horizontal, 40)
                    }
                    .padding(.top, 15)
                }
                .padding(.top, 10)
            }

            Spacer()
        }
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .alert(isPresented: $showWinAlert) {
            Alert(
                title: Text("Spiel beendet"),
                message: Text("\(winnerName) hat gewonnen!"),
                dismissButton: .default(Text("OK"), action: resetGame)
            )
        }
    }

    // MARK: - UI-Komponenten

    private func modeButton(_ title: String, _ value: Int) -> some View {
        Button {
            selectedGame = value
        } label: {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selectedGame == value ? Color.dvModeActive : Color.dvMode)
                )
        }
        .buttonStyle(.plain)
    }

    private func multButton(_ title: String, _ value: Int, color: Color) -> some View {
        Button {
            multiplier = value
        } label: {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .frame(width: 80, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(multiplier == value ? color.opacity(1.0) : color.opacity(0.4))
                )
                .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }

    private func bullButton(_ title: String, value: Int) -> some View {
        Button { addScore(value) } label: {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 100, height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.dvMode)
                )
                .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Spiellogik

    private func startGame() {
        guard let selectedGame = selectedGame, !newPlayer1.isEmpty, !newPlayer2.isEmpty else { return }
        players = [
            Player(name: newPlayer1, remaining: selectedGame),
            Player(name: newPlayer2, remaining: selectedGame)
        ]
        currentPlayerIndex = 0
        multiplier = 1
        dartsThrown = 0
        gameStarted = true
        speak("Spiel gestartet mit \(selectedGame) Punkten.")
    }

    private func resetGame() {
        gameStarted = false
        players.removeAll()
        selectedGame = nil
        newPlayer1 = ""
        newPlayer2 = ""
        multiplier = 1
        dartsThrown = 0
        speak("Spiel gestoppt.")
    }

    private func addScore(_ base: Int) {
        guard gameStarted, !players.isEmpty else { return }

        let current = players[currentPlayerIndex]
        let score = base * multiplier
        let newRemaining = current.remaining - score

        // --- Überwurf prüfen ---
        if newRemaining < 0 {
            speak("Überworfen! Nächster Spieler.")
            nextPlayer()
            return
        }

        // --- Double-Out-Regel prüfen ---
        if newRemaining == 0 {
            if doubleOut {
                // nur gültig, wenn letzter Wurf ein Double
                if multiplier == 2 {
                    winnerName = current.name
                    showWinAlert = true
                    speak("\(current.name) gewinnt mit Double Out!")
                    return
                } else {
                    // nicht mit Double getroffen → Bust
                    speak("Kein Double Out! Überworfen.")
                    nextPlayer()
                    return
                }
            } else {
                // normales Finish
                winnerName = current.name
                showWinAlert = true
                speak("\(current.name) gewinnt!")
                return
            }
        }

        // Wenn kein Sieg und kein Bust → normaler Treffer
        players[currentPlayerIndex].remaining = newRemaining
        speak("\(score) Punkte. Rest \(newRemaining)")

        dartsThrown += 1
        if dartsThrown == 3 {
            dartsThrown = 0
            nextPlayer()
        }

        multiplier = 1
    }

    private func nextPlayer() {
        dartsThrown = 0
        multiplier = 1  // Reset multiplier when changing player
        currentPlayerIndex = (currentPlayerIndex + 1) % players.count
        speak("Nächster Spieler: \(players[currentPlayerIndex].name)")
    }

    private func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "de-DE")
        u.rate = 0.45
        synthesizer.speak(u)
    }
}

private func stylishTextField(_ placeholder: String, text: Binding<String>) -> some View {
    TextField(placeholder, text: text)
        .padding(.horizontal, 16)
        .frame(height: 55)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.1), radius: 5, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.dvPrimary.opacity(0.3), lineWidth: 1)
        )
        .font(.system(size: 18, weight: .medium))
        .foregroundColor(.dvInk)
        .autocapitalization(.words)
}

