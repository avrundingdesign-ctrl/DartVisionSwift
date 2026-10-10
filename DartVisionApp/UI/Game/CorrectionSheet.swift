import SwiftUI
import Foundation
import CoreGraphics

/// Korrektur des aktuellen bzw. letzten Zugs – per Tippen aufs Board oder über Tasten.
struct CorrectionSheet: View {
    let session: GameSession
    @Environment(\.dismiss) private var dismiss

    @State private var turnID: UUID?
    @State private var playerName = ""
    @State private var entries: [GameSession.CorrectionEntry] = []
    @State private var selected = 0
    @State private var useBoard = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                header
                slots
                Picker("Eingabe", selection: $useBoard) {
                    Text("Board antippen").tag(true)
                    Text("Tasten").tag(false)
                }
                .pickerStyle(.segmented)

                if useBoard {
                    DartboardView(markers: markers, highlight: selectedHit) { point in
                        set(BoardGeometry.hit(at: point), point: point)
                    }
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                } else {
                    HitKeypad { hit in
                        set(hit, point: nil)
                    }
                    Spacer(minLength: 0)
                }

                Button(role: .destructive) {
                    removeSelected()
                } label: {
                    Label("Dart \(selected + 1) entfernen", systemImage: "trash")
                }
                .buttonStyle(DVButtonStyle(kind: .destructive, height: 46))
                .disabled(selected >= entries.count)
            }
            .padding(16)
            .background(Color.dvBackground)
            .navigationTitle("Korrektur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        if let turnID {
                            session.applyCorrection(turnID: turnID, entries: entries)
                        }
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(turnID == nil)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Color.dvBackground)
        .onAppear(perform: load)
    }

    // MARK: - Teile

    private var header: some View {
        let preview = turnID.flatMap { session.previewCorrection(turnID: $0, entries: entries) }
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(playerName)
                    .font(.dvRounded(20, weight: .bold))
                    .foregroundStyle(Color.dvText)
                Text("Tippe einen Dart an und wähle das richtige Feld.")
                    .font(.dvRounded(13, weight: .medium))
                    .foregroundStyle(Color.dvTextSecondary)
            }
            Spacer()
            if let preview {
                VStack(alignment: .trailing, spacing: 2) {
                    if let bust = preview.bust {
                        Text(bust.message)
                            .font(.dvRounded(15, weight: .bold))
                            .foregroundStyle(Color.dvRed)
                    } else if preview.isCheckout {
                        Text("Checkout!")
                            .font(.dvRounded(15, weight: .bold))
                            .foregroundStyle(Color.dvGreen)
                    } else {
                        Text("\(preview.scored) Pkt.")
                            .font(.dvNumber(18, weight: .bold))
                            .foregroundStyle(Color.dvText)
                    }
                    Text("Rest \(preview.endRemaining)")
                        .font(.dvNumber(13, weight: .medium))
                        .foregroundStyle(Color.dvTextSecondary)
                }
            }
        }
    }

    private var slots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                let entry = index < entries.count ? entries[index] : nil
                let isSelected = index == selected
                let selectable = index <= entries.count
                Button {
                    if selectable { selected = index }
                } label: {
                    VStack(spacing: 2) {
                        Text(entry?.hit.label ?? (selectable ? "+" : "–"))
                            .font(.dvNumber(24, weight: .heavy))
                        Text(entry.map { "\($0.hit.points) Pkt." } ?? "Dart \(index + 1)")
                            .font(.dvRounded(12, weight: .medium))
                            .foregroundStyle(Color.dvTextSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 66)
                    .foregroundStyle(entry == nil ? Color.dvTextTertiary : Color.dvText)
                    .background(Color.dvSurfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isSelected ? Color.dvRed : Color.dvStroke, lineWidth: isSelected ? 2 : 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!selectable)
            }
        }
    }

    private var markers: [BoardMarker] {
        entries.enumerated().compactMap { index, entry in
            guard let point = entry.boardPoint ?? BoardGeometry.representativePoint(for: entry.hit) else { return nil }
            return BoardMarker(id: entry.id, position: point, label: "\(index + 1)",
                               style: index == selected ? .current : .previous)
        }
    }

    private var selectedHit: Hit? {
        selected < entries.count ? entries[selected].hit : nil
    }

    // MARK: - Logik

    private func load() {
        guard turnID == nil, let turn = session.correctableTurn else { return }
        turnID = turn.id
        playerName = session.players[turn.playerIndex]
        entries = turn.darts.map { GameSession.CorrectionEntry(id: $0.id, hit: $0.hit, boardPoint: $0.boardPoint) }
        if let uncertain = turn.darts.firstIndex(where: { $0.isUncertain }) {
            selected = uncertain
        } else {
            selected = min(entries.count, 2)
        }
    }

    private func set(_ hit: Hit, point: CGPoint?) {
        if selected < entries.count {
            entries[selected].hit = hit
            entries[selected].boardPoint = point
        } else if entries.count < 3 {
            entries.append(GameSession.CorrectionEntry(id: UUID(), hit: hit, boardPoint: point))
            selected = entries.count - 1
        }
        if selected < 2 && selected < entries.count {
            selected += 1
        }
    }

    private func removeSelected() {
        guard selected < entries.count else { return }
        entries.remove(at: selected)
        selected = min(selected, entries.count)
    }
}
