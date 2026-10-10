import SwiftUI
import Foundation

struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var newPlayerName = ""
    @State private var showSettings = false
    @FocusState private var nameFieldFocused: Bool

    private var validPlayers: [String] {
        app.settings.players.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if let saved = app.savedMatch {
                    ResumeCard(match: saved,
                               onResume: { app.resumeSavedGame() },
                               onDiscard: { withAnimation { app.discardSavedMatch() } })
                }
                playersSection
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "Spiel")
                    GameOptionsCard(settings: app.settings)
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "Zählung")
                    InputModeCard(settings: app.settings)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(alignment: .topTrailing) {
            DartboardView()
                .frame(width: 320)
                .opacity(0.07)
                .rotationEffect(.degrees(-12))
                .offset(x: 120, y: -90)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .safeAreaInset(edge: .bottom) { startBar }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text("DartVision")
                    .font(.dvWordmark(48))
                    .foregroundStyle(Color.dvText)
                Text("Automatisch zählen – einfach werfen.")
                    .font(.dvRounded(14, weight: .medium))
                    .foregroundStyle(Color.dvTextSecondary)
            }
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.dvTextSecondary)
                    .frame(width: 44, height: 44)
                    .background(Color.dvSurface, in: Circle())
            }
            .accessibilityLabel("Einstellungen")
        }
        .padding(.top, 8)
    }

    // MARK: - Spieler

    private var playersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(text: "Spieler")
                Spacer()
                if app.settings.players.count > 1 {
                    Button {
                        withAnimation(.snappy) { app.settings.players.shuffle() }
                    } label: {
                        Label("Reihenfolge mischen", systemImage: "shuffle")
                            .font(.dvRounded(13, weight: .semibold))
                    }
                    .foregroundStyle(Color.dvTextSecondary)
                }
            }

            VStack(spacing: 8) {
                ForEach(Array(app.settings.players.enumerated()), id: \.offset) { index, name in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.dvNumber(14, weight: .bold))
                            .foregroundStyle(Color.dvBackground)
                            .frame(width: 28, height: 28)
                            .background(index == 0 ? Color.dvRed : Color.dvCream, in: Circle())
                        Text(name)
                            .font(.dvRounded(17, weight: .semibold))
                            .foregroundStyle(Color.dvText)
                            .lineLimit(1)
                        Spacer()
                        if index == 0 {
                            Text("Anwurf")
                                .font(.dvRounded(11, weight: .bold))
                                .foregroundStyle(Color.dvTextTertiary)
                        }
                        Button {
                            withAnimation(.snappy) { removePlayer(at: index) }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.dvTextTertiary)
                                .frame(width: 34, height: 34)
                        }
                        .accessibilityLabel("\(name) entfernen")
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 4)
                    .padding(.vertical, 6)
                    .background(Color.dvSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if app.settings.players.count < 6 {
                    HStack(spacing: 10) {
                        TextField("", text: $newPlayerName,
                                  prompt: Text("Spieler hinzufügen").foregroundColor(Color.dvTextTertiary))
                            .font(.dvRounded(17, weight: .medium))
                            .foregroundStyle(Color.dvText)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($nameFieldFocused)
                            .onSubmit(addPlayer)
                        Button(action: addPlayer) {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(trimmedName.isEmpty ? Color.dvSurfaceRaised : Color.dvRed, in: Circle())
                        }
                        .disabled(trimmedName.isEmpty)
                        .accessibilityLabel("Spieler hinzufügen")
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 6)
                    .padding(.vertical, 6)
                    .background(Color.dvSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.dvStroke, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    )
                }
            }
        }
    }

    private var trimmedName: String {
        newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addPlayer() {
        let name = trimmedName
        guard !name.isEmpty, app.settings.players.count < 6 else { return }
        withAnimation(.snappy) { app.settings.players.append(name) }
        newPlayerName = ""
    }

    private func removePlayer(at index: Int) {
        guard app.settings.players.indices.contains(index) else { return }
        app.settings.players.remove(at: index)
    }

    // MARK: - Start

    private var startBar: some View {
        VStack(spacing: 8) {
            Button {
                nameFieldFocused = false
                app.beginNewGame()
            } label: {
                Label(app.settings.inputMode == .camera ? "Kalibrieren & starten" : "Spiel starten",
                      systemImage: app.settings.inputMode == .camera ? "camera.viewfinder" : "play.fill")
            }
            .buttonStyle(DVButtonStyle(kind: .primary, height: 58))
            .disabled(validPlayers.isEmpty)

            Text(validPlayers.isEmpty ? "Mindestens einen Spieler hinzufügen" : app.settings.x01.summary)
                .font(.dvRounded(12, weight: .medium))
                .foregroundStyle(Color.dvTextTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .background(
            LinearGradient(colors: [Color.dvBackground.opacity(0), Color.dvBackground, Color.dvBackground],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }
}

// MARK: - Spieloptionen

private struct GameOptionsCard: View {
    @Bindable var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            option("Startpunkte") {
                ChipPicker(options: [301, 501, 701], selection: $settings.x01.startScore) { "\($0)" }
            }
            option("Finish") {
                ChipPicker(options: OutRule.allCases, selection: $settings.x01.outRule) { rule in
                    switch rule {
                    case .straight: return "Single"
                    case .double: return "Double"
                    case .master: return "Master"
                    }
                }
            }
            option("Start") {
                ChipPicker(options: InRule.allCases, selection: $settings.x01.inRule) { rule in
                    rule == .straight ? "Single In" : "Double In"
                }
            }
            option("Legs (Best of)") {
                ChipPicker(options: [1, 3, 5, 7], selection: $settings.x01.bestOfLegs) { "\($0)" }
            }
        }
        .dvCard()
    }

    private func option<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.dvRounded(13, weight: .semibold))
                .foregroundStyle(Color.dvTextSecondary)
            content()
        }
    }
}

// MARK: - Eingabeart

private struct InputModeCard: View {
    @Bindable var settings: AppSettings

    var body: some View {
        HStack(spacing: 10) {
            modeButton(.camera, title: "Kamera",
                       subtitle: settings.backend == .onDevice ? "KI auf dem iPhone" : "KI auf dem Server",
                       icon: "camera.viewfinder")
            modeButton(.manual, title: "Manuell", subtitle: "Punkte eintippen", icon: "square.grid.3x3.fill")
        }
    }

    private func modeButton(_ mode: InputMode, title: String, subtitle: String, icon: String) -> some View {
        let selected = settings.inputMode == mode
        return Button {
            withAnimation(.snappy) { settings.inputMode = mode }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? Color.dvRed : Color.dvTextSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.dvRounded(17, weight: .bold))
                        .foregroundStyle(Color.dvText)
                    Text(subtitle)
                        .font(.dvRounded(12, weight: .medium))
                        .foregroundStyle(Color.dvTextSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.dvSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(selected ? Color.dvRed : Color.dvStroke, lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Fortsetzen

private struct ResumeCard: View {
    let match: X01Match
    let onResume: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        let snapshot = match.snapshot()
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Offenes Spiel", systemImage: "clock.arrow.circlepath")
                    .font(.dvRounded(14, weight: .bold))
                    .foregroundStyle(Color.dvGold)
                Spacer()
                Text(match.settings.summary)
                    .font(.dvRounded(12, weight: .medium))
                    .foregroundStyle(Color.dvTextTertiary)
                    .lineLimit(1)
            }
            Text(zip(match.players, snapshot.remaining).map { "\($0) \($1)" }.joined(separator: "  ·  "))
                .font(.dvNumber(16, weight: .semibold))
                .foregroundStyle(Color.dvText)
                .lineLimit(2)
            HStack(spacing: 10) {
                Button("Verwerfen", action: onDiscard)
                    .buttonStyle(DVButtonStyle(kind: .secondary, height: 44))
                Button("Fortsetzen", action: onResume)
                    .buttonStyle(DVButtonStyle(kind: .primary, height: 44))
            }
        }
        .dvCard()
    }
}
