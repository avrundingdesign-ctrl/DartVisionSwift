import SwiftUI
import Foundation
import CoreGraphics

struct GameView: View {
    @Environment(AppModel.self) private var app
    let session: GameSession

    @State private var showCorrection = false
    @State private var showCameraPreview = false
    @State private var confirmExit = false
    @State private var manualBoardInput = false

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height * 1.1
            Group {
                if wide {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 12) {
                            topBar
                            scoreboard
                            turnCard
                            Spacer(minLength: 0)
                            actionBar
                        }
                        .frame(maxWidth: 460)
                        inputArea
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(16)
                } else {
                    VStack(spacing: 12) {
                        topBar
                        scoreboard
                        turnCard
                        inputArea
                            .frame(maxHeight: .infinity)
                        actionBar
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(Color.dvBackground.ignoresSafeArea())
        .overlay { bannerOverlay }
        .overlay { phaseOverlay }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: session.banner)
        .animation(.easeInOut(duration: 0.3), value: session.snapshot.phase)
        .sheet(isPresented: $showCorrection) {
            CorrectionSheet(session: session)
        }
        .confirmationDialog("Spiel beenden?", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("Beenden – später fortsetzen", role: .destructive) { app.endSession() }
            Button("Weiterspielen", role: .cancel) {}
        }
        .onChange(of: session.snapshot.matchWinner) { _, winner in
            guard winner != nil else { return }
            Task {
                try? await Task.sleep(for: .seconds(2.2))
                if session.snapshot.matchWinner != nil { app.showResults() }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: session.snapshot.stats.reduce(0) { $0 + $1.darts })
    }

    // MARK: - Kopfzeile

    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(legTitle)
                    .font(.dvRounded(16, weight: .bold))
                    .foregroundStyle(Color.dvText)
                Text(session.match.settings.summary)
                    .font(.dvRounded(12, weight: .medium))
                    .foregroundStyle(Color.dvTextTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            statusPill
            Menu {
                if session.inputMode == .camera {
                    Button(session.isPaused ? "Fortsetzen" : "Pausieren",
                           systemImage: session.isPaused ? "play.fill" : "pause.fill") {
                        session.togglePause()
                    }
                    Button(showCameraPreview ? "Kamerabild ausblenden" : "Kamerabild zeigen",
                           systemImage: "camera") {
                        withAnimation { showCameraPreview.toggle() }
                    }
                    Button("Neu kalibrieren", systemImage: "scope") {
                        session.requestRecalibration()
                    }
                }
                Button("Spiel beenden", systemImage: "xmark.circle", role: .destructive) {
                    confirmExit = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.dvText)
                    .frame(width: 40, height: 40)
                    .background(Color.dvSurface, in: Circle())
            }
            .accessibilityLabel("Menü")
        }
    }

    private var legTitle: String {
        let leg = session.snapshot.legIndex + 1
        return session.match.settings.bestOfLegs > 1 ? "Leg \(leg) · Best of \(session.match.settings.bestOfLegs)" : "Leg \(leg)"
    }

    @ViewBuilder
    private var statusPill: some View {
        switch session.status {
        case .manual:
            StatusPill(text: "Manuell", systemImage: "hand.tap.fill", tint: .dvTextSecondary)
        case .starting:
            StatusPill(text: "Startet …", systemImage: "hourglass", tint: .dvTextSecondary, pulsing: true)
        case .watching:
            StatusPill(text: "KI bereit", systemImage: "eye.fill", tint: .dvGreen, pulsing: session.isAnalyzing)
        case .holdStill:
            StatusPill(text: "Handy ruhig halten", systemImage: "iphone.gen3.radiowaves.left.and.right", tint: .dvGold)
        case .pullDarts:
            StatusPill(text: "Darts ziehen", systemImage: "hand.raised.fill", tint: .dvGold, pulsing: true)
        case .recalibrating:
            StatusPill(text: "Kalibriere …", systemImage: "scope", tint: .dvGold, pulsing: true)
        case .paused:
            StatusPill(text: "Pausiert", systemImage: "pause.fill", tint: .dvTextSecondary)
        case .error:
            StatusPill(text: "Problem", systemImage: "exclamationmark.triangle.fill", tint: .dvRed)
        }
    }

    // MARK: - Scoreboard

    @ViewBuilder
    private var scoreboard: some View {
        let count = session.players.count
        if count <= 2 {
            HStack(spacing: 10) {
                ForEach(0..<count, id: \.self) { index in
                    playerCard(index, compact: false)
                }
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<count, id: \.self) { index in
                            playerCard(index, compact: true)
                                .frame(width: 150)
                                .id(index)
                        }
                    }
                }
                .onChange(of: session.snapshot.currentPlayer) { _, player in
                    withAnimation { proxy.scrollTo(player, anchor: .center) }
                }
            }
        }
        if case .error(let message) = session.status {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.dvRounded(13, weight: .semibold))
                .foregroundStyle(Color.dvRed)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func playerCard(_ index: Int, compact: Bool) -> some View {
        let snapshot = session.snapshot
        return PlayerScoreCard(
            name: session.players[index],
            remaining: snapshot.remaining[index],
            stats: snapshot.stats[index],
            showLegs: session.match.settings.bestOfLegs > 1,
            isActive: index == snapshot.currentPlayer && snapshot.legWinner == nil,
            compact: compact
        )
    }

    // MARK: - Aktueller Zug

    private var turnCard: some View {
        let turn = session.displayedTurn
        let remaining = session.snapshot.remaining[turn.player]
        let total = turn.result?.scored ?? turn.darts.reduce(0) { $0 + $1.hit.points }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(turn.isFinished ? "AUFNAHME" : "AM WURF")
                        .font(.dvRounded(11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.dvTextTertiary)
                    Text(session.players[turn.player])
                        .font(.dvRounded(24, weight: .bold))
                        .foregroundStyle(Color.dvText)
                        .lineLimit(1)
                    turnStatus(turn)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("REST")
                        .font(.dvRounded(11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.dvTextTertiary)
                    Text("\(remaining)")
                        .font(.dvNumber(62, weight: .heavy))
                        .foregroundStyle(Color.dvText)
                        .contentTransition(.numericText(value: Double(remaining)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }

            if let route = session.checkoutRoute {
                HStack(spacing: 8) {
                    Image(systemName: "target")
                        .font(.system(size: 14, weight: .bold))
                    ForEach(Array(route.enumerated()), id: \.offset) { _, hit in
                        Text(hit.label)
                            .font(.dvNumber(15, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.dvGold.opacity(0.16), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color.dvGold)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Checkout: " + route.map(\.spokenText).joined(separator: ", "))
            }

            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    DartChip(dart: index < turn.darts.count ? turn.darts[index] : nil,
                             index: index,
                             isNext: !turn.isFinished && index == turn.darts.count)
                        .onTapGesture {
                            if session.correctableTurn != nil { showCorrection = true }
                        }
                }
            }

            HStack {
                Text(turnFooter(turn))
                    .font(.dvRounded(13, weight: .medium))
                    .foregroundStyle(Color.dvTextSecondary)
                Spacer()
                Text("\(total)")
                    .font(.dvNumber(26, weight: .heavy))
                    .foregroundStyle(turn.result?.isBust == true ? Color.dvRed : Color.dvText)
                    .contentTransition(.numericText(value: Double(total)))
            }
        }
        .dvCard()
        .animation(.snappy(duration: 0.3), value: turn.darts)
    }

    @ViewBuilder
    private func turnStatus(_ turn: GameSession.DisplayedTurn) -> some View {
        if let bust = turn.result?.bust {
            Label(bust.message, systemImage: "xmark.octagon.fill")
                .font(.dvRounded(13, weight: .bold))
                .foregroundStyle(Color.dvRed)
        } else if turn.result?.isCheckout == true {
            Label("Checkout!", systemImage: "checkmark.seal.fill")
                .font(.dvRounded(13, weight: .bold))
                .foregroundStyle(Color.dvGreen)
        } else if turn.isFinished && session.awaitingTakeout {
            Label("Darts ziehen", systemImage: "hand.raised.fill")
                .font(.dvRounded(13, weight: .bold))
                .foregroundStyle(Color.dvGold)
        } else if let opened = session.snapshot.opened[safe: turn.player], !opened {
            Text("Double In nötig")
                .font(.dvRounded(13, weight: .semibold))
                .foregroundStyle(Color.dvGold)
        }
    }

    private func turnFooter(_ turn: GameSession.DisplayedTurn) -> String {
        if turn.isFinished {
            return session.inputMode == .camera ? "Zum Korrigieren auf einen Dart tippen" : "Aufnahme beendet"
        }
        let left = 3 - turn.darts.count
        switch left {
        case 3: return session.inputMode == .camera ? "Warte auf den ersten Dart …" : "Erster Dart"
        case 1: return "Noch 1 Dart"
        default: return "Noch \(left) Darts"
        }
    }

    // MARK: - Board / Eingabe

    @ViewBuilder
    private var inputArea: some View {
        if session.inputMode == .camera {
            ZStack(alignment: .topTrailing) {
                DartboardView(markers: markers) { _ in
                    if session.correctableTurn != nil { showCorrection = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showCameraPreview {
                    CameraPreviewView(camera: app.camera, fill: true)
                        .frame(width: 120, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.dvStroke, lineWidth: 1)
                        )
                        .transition(.scale(scale: 0.8, anchor: .topTrailing).combined(with: .opacity))
                }
            }
        } else {
            VStack(spacing: 10) {
                Picker("Eingabe", selection: $manualBoardInput) {
                    Text("Tasten").tag(false)
                    Text("Board").tag(true)
                }
                .pickerStyle(.segmented)

                if manualBoardInput {
                    DartboardView(markers: markers) { point in
                        session.addManualDart(BoardGeometry.hit(at: point), boardPoint: point)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HitKeypad { hit in
                        session.addManualDart(hit)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var markers: [BoardMarker] {
        let turn = session.displayedTurn
        return turn.darts.enumerated().compactMap { index, dart in
            guard let point = dart.boardPoint else { return nil }
            let style: BoardMarker.Style = dart.isUncertain ? .uncertain : (turn.isFinished ? .previous : .current)
            return BoardMarker(id: dart.id, position: point, label: "\(index + 1)", style: style)
        }
    }

    // MARK: - Aktionen

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                session.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(DVButtonStyle(kind: .secondary))
            .frame(width: 64)
            .accessibilityLabel("Letzten Dart zurücknehmen")

            Button {
                showCorrection = true
            } label: {
                Label("Korrigieren", systemImage: "pencil")
            }
            .buttonStyle(DVButtonStyle(kind: .secondary))
            .disabled(session.correctableTurn == nil)

            Button {
                session.advance()
            } label: {
                Label(advanceTitle, systemImage: "arrow.right")
            }
            .buttonStyle(DVButtonStyle(kind: .primary))
            .disabled(session.snapshot.matchWinner != nil)
        }
    }

    private var advanceTitle: String {
        switch session.snapshot.phase {
        case .legWon: return "Nächstes Leg"
        case .matchWon: return "Fertig"
        case .throwing:
            if session.snapshot.openTurn != nil { return "Zug beenden" }
            return "Weiter"
        }
    }

    // MARK: - Overlays

    @ViewBuilder
    private var bannerOverlay: some View {
        if let banner = session.banner {
            BannerView(banner: banner)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var phaseOverlay: some View {
        switch session.snapshot.phase {
        case .legWon(let winner):
            LegWonOverlay(
                title: "Leg an \(session.players[winner])",
                subtitle: legScoreLine,
                hint: session.inputMode == .camera ? "Darts ziehen – das nächste Leg startet automatisch." : nil,
                buttonTitle: "Nächstes Leg",
                action: { session.advance() }
            )
            .transition(.opacity)
        case .matchWon(let winner):
            LegWonOverlay(
                title: "\(session.players[winner]) gewinnt!",
                subtitle: legScoreLine,
                hint: nil,
                buttonTitle: "Ergebnis anzeigen",
                action: { app.showResults() }
            )
            .transition(.opacity)
        case .throwing:
            EmptyView()
        }
    }

    private var legScoreLine: String {
        zip(session.players, session.snapshot.legsWon).map { "\($0) \($1)" }.joined(separator: " : ")
    }
}

// MARK: - Bausteine

private struct BannerView: View {
    let banner: GameSession.Banner

    var body: some View {
        switch banner {
        case .bust(let message):
            VStack(spacing: 4) {
                Text("ÜBERWORFEN")
                    .font(.dvRounded(30, weight: .black))
                Text(message)
                    .font(.dvRounded(14, weight: .semibold))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .background(Color.dvRed, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.dvRed.opacity(0.5), radius: 30)
        case .oneEighty:
            Text("180")
                .font(.dvNumber(96, weight: .black))
                .foregroundStyle(
                    LinearGradient(colors: [Color.dvGold, Color(hex: 0xFF7A3D)], startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: Color.dvGold.opacity(0.6), radius: 30)
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        case .info(let text):
            Label(text, systemImage: "info.circle.fill")
                .font(.dvRounded(15, weight: .semibold))
                .foregroundStyle(Color.dvText)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.dvSurfaceRaised, in: Capsule())
        }
    }
}

private struct LegWonOverlay: View {
    let title: String
    let subtitle: String
    let hint: String?
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.dvGold)
                    .symbolEffect(.bounce, value: title)
                Text(title)
                    .font(.dvRounded(28, weight: .heavy))
                    .foregroundStyle(Color.dvText)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.dvNumber(17, weight: .semibold))
                    .foregroundStyle(Color.dvTextSecondary)
                if let hint {
                    Text(hint)
                        .font(.dvRounded(13, weight: .medium))
                        .foregroundStyle(Color.dvTextTertiary)
                        .multilineTextAlignment(.center)
                }
                Button(buttonTitle, action: action)
                    .buttonStyle(DVButtonStyle(kind: .primary))
                    .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: 360)
            .dvCard(padding: 0)
            .padding(24)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
