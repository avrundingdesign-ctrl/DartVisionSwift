import SwiftUI

struct DartVisionUI: View {
    // MARK: - Bindings / App State
    @Binding var gameState: GameState
    @Binding var selectedGame: Int?
    @Binding var remaining: Int
    @Binding var isPaused: Bool
    @Binding var players: [String]
    @Binding var doubleOut: Bool
    @Binding var currentPlayerIndex: Int
    @Binding var remainingScores: [Int]

    // MARK: - Actions
    var startAction: () -> Void
    var stopAction: () -> Void
    var pauseAction: () -> Void
    var uploadHandler: (UIImage) -> Void
    var correctionAction: () -> Void = {}   // optional: Logik später

    // MARK: - Models
    @ObservedObject var cameraModel: CameraModel

    // MARK: - Local UI State
    @State private var selectedTab: String = "Vision"
    @State private var showCorrection = false
    @State private var correctedThrows: [Int] = [] // für spätere Verwendung
    @State private var showModeSelection = false
    
    @State private var showCalibratedPopup = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ---------- Inhalt ----------
                VStack(spacing: 0) {
                    VStack(spacing: 15) {
                        Spacer(minLength: 35)

                        // Titel & Setup nur, wenn KEIN Spiel aktiv
                        if gameState != .active {
                            Text("DartVision")
                                .font(.custom("Italiana-Regular", size: 64))
                                .foregroundColor(.dvInk)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 15)
                                .tracking(3)

                            HStack(spacing: 20) {
                                AddPlayerButtonView(players: $players)
                                FilterButtonView(selectedGame: $selectedGame, doubleOut: $doubleOut)

                            }
                            .padding(.top, 15)
                        }

                        // Start-Button (vor Spielstart)
                        if gameState == .idle || gameState == .ready {
                            controlStrip()
                                .padding(.top, 10)
                        }

                        // Spieleranzeige im aktiven Spiel
                        if gameState == .active {
                            playerList()
                                .padding(.horizontal, 10)
                                .transition(.opacity)
                            
                            CurrentThrowRow(scores: cameraModel.currentGame.dartScores)
                                .padding(.horizontal,10)
                                .padding(.top, 10)
                        }
                        
                        // Kamera-Vorschau (oder Platzhalter)
                        cameraArea()
                            .frame(height: 220)
                            .padding(.vertical, 10)

                        // Controls (Stop/Pause + Korrektur) im aktiven Spiel
                        if gameState == .active {
                            controlStrip()
                                .padding(.top, 8)
                                .padding(.bottom, 12)
                        }
                        // --- Neuer Modi-Button unterhalb der Kamera ---
                        if gameState != .active {
                            Button(action: {
                                showModeSelection = true
                            }) {
                                Label("Modi", systemImage: "gamecontroller")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 30)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.dvPrimary)
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)
                            .sheet(isPresented: $showModeSelection) {
                                GameModeSelectionView(cameraModel: cameraModel)
                                    .presentationDetents([.fraction(0.4)])
                            }
                        }


                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)

                    // ---------- Bottom-Bar ----------
                    if gameState != .active {
                        bottomBar(geo: geo)
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                .background(Color.white)

                // ---------- Overlay: ScoreCorrection ----------
                if showCorrection {
                    ScoreCorrectionView(
                        onConfirm: { total in
                            applyCorrection(total)   // 🧮 Score anpassen
                            isPaused = false          // 🟢 Spiel fortsetzen
                            showCorrection = false    // Fenster schließen
                        },
                        onCancel: {
                            showCorrection = false
                            isPaused = false          // optional: Spiel auch nach Abbruch fortsetzen
                        }
                    )

                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(response: 0.25, dampingFraction: 0.9), value: showCorrection)
                }
                calibrationStatusOverlay()
            }
        }
        .onChange(of: cameraModel.currentGame.keypoints != nil) { hasKeypoints in
                    if hasKeypoints {
                        // Keypoints sind da -> Zeige "Kalibriert" kurz an
                        withAnimation {
                            showCalibratedPopup = true
                        }
                        
                        // Nach 2 Sekunden ausblenden
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            withAnimation {
                                showCalibratedPopup = false
                            }
                        }
                    } else {
                        // Keypoints sind weg (Motion Detector) -> "Warten" kommt automatisch durch die View-Condition
                        // Wir schalten das Erfolgs-Popup sofort aus, falls es noch an war
                        showCalibratedPopup = false
                    }
                }
    }
    
    private func applyCorrection(_ correctedScore: Int) {
        guard remainingScores.indices.contains(currentPlayerIndex) else { return }

        // alten Wert holen
        let oldRemaining = remainingScores[currentPlayerIndex]

        // 🔹 neuen Rest berechnen (einfaches Beispiel)
        let newRemaining = max(oldRemaining - correctedScore, 0)

        remainingScores[currentPlayerIndex] = newRemaining
        remaining = newRemaining

        print("🧮 Korrektur angewendet: \(players[currentPlayerIndex]) neuer Rest: \(newRemaining)")
    }

    // MARK: - Components

    @ViewBuilder
    private func controlStrip() -> some View {
        switch gameState {
        case .idle, .ready:
            glassButton(title: "Start Game",
                        enabled: selectedGame != nil && !players.isEmpty) {
                startAction()
            }

        case .active:
            VStack(spacing: 12) {
                // Stop / Pause
                HStack(spacing: 20) {
                    glassButton(icon: "record.circle.fill", color: .dvAccentRed) {
                        stopAction()
                        cameraModel.currentGame.keypoints = nil
                    }
                    glassButton(icon: isPaused ? "play.fill" : "pause.fill", color: .dvPrimary) {
                        pauseAction()
                    }
                }

                // Korrektur-Button (volle Breite wie Kamera-GUI)
                Button(action: {
                    showCorrection = true
                    isPaused = true   // 🟡 Spiel pausieren, sobald Fenster geöffnet
                }) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.dvInk.opacity(0.12))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .overlay(
                            HStack(spacing: 8) {
                                Image(systemName: "wand.and.rays")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.dvInk)
                                Text("Korrektur")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.dvInk)
                            }
                        )
                }
                .buttonStyle(.plain)

                .accessibilityLabel("Korrektur")
            }
        }
    }

    @ViewBuilder
    private func cameraArea() -> some View {
        ZStack {
            if gameState == .active {
                CameraPreview(session: cameraModel.session)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.05))
                    .overlay(
                        Text("CAMERA PREVIEW")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.black.opacity(0.6))
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    @ViewBuilder
    private func playerList() -> some View {
        VStack(spacing: 16) {
            ForEach(players.indices, id: \.self) { i in
                let name = players[i]
                let score = i < remainingScores.count ? remainingScores[i] : 0

                HStack {
                    Text(name)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundColor(i == currentPlayerIndex ? Color.dvPrimary : .gray)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(score)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(i == currentPlayerIndex ? .dvPrimary : .gray)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(i == currentPlayerIndex ? Color.dvPrimary : Color.clear, lineWidth: 2)
                        )
                )
            }
        }
    }

    @ViewBuilder
    private func bottomBar(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            Divider().opacity(0.15)
            HStack(spacing: 40) {
                bottomTab(title: "Vision")
                bottomTab(title: "Analog")
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 10)
            .padding(.bottom, geo.safeAreaInsets.bottom + 6)
            .background(Color.white)
            .shadow(color: .black.opacity(0.1), radius: 8, y: -3)
        }
    }

    private func glassButton(title: String? = nil,
                             icon: String? = nil,
                             enabled: Bool = true,
                             color: Color = .dvPrimary,
                             action: @escaping () -> Void) -> some View {
        Button(action: { if enabled { action() } }) {
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(enabled ? 1 : 0.4))
                .frame(maxWidth: .infinity)
                .frame(height: 70)
                .overlay(
                    Group {
                        if let title = title {
                            Text(title)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                        } else if let icon = icon {
                            Image(systemName: icon)
                                .foregroundColor(.white)
                                .font(.system(size: 20, weight: .bold))
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.6)
    }

    // MARK: - Bottom-Bar
    private func bottomTab(title: String) -> some View {
        if title == "Analog" {
            return AnyView(
                NavigationLink(destination: AnalogView()) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.dvInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.clear)
                        )
                }
                .buttonStyle(.plain)
            )
        } else {
            return AnyView(
                Button {
                    selectedTab = title
                } label: {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(selectedTab == title ? .white : .dvInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedTab == title ? Color.dvInk : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            )
        }
    }
    @ViewBuilder
        private func calibrationStatusOverlay() -> some View {
            // Nur anzeigen, wenn Spiel aktiv ist
            if gameState == .active {
                VStack {
                    // Positionierung: Eher oben, damit es auffällt, aber nicht den Score verdeckt
                    Spacer().frame(height: 60)
                    
                    if cameraModel.currentGame.keypoints == nil {
                        // 🟡 FALL 1: Keine Keypoints -> WARTEN (Dauerhaft)
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(.black)
                            Text("Warten auf Kalibrierung...")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.black)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.yellow)
                                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    else if showCalibratedPopup {
                        // 🟢 FALL 2: Keypoints frisch da -> KALIBRIERT (Kurzzeitig)
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                            Text("Kalibriert")
                                .font(.system(size: 18, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.green) // Oder Color.dvPrimary für Lila
                                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    Spacer()
                }
                .animation(.easeInOut, value: cameraModel.currentGame.keypoints == nil)
                .animation(.easeInOut, value: showCalibratedPopup)
            }
        }
}
