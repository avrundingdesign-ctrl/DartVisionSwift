import SwiftUI
import Foundation
import CoreGraphics

/// Ein Dart des aktuellen Zugs.
struct DartChip: View {
    let dart: DartThrow?
    let index: Int
    var isNext = false

    var body: some View {
        VStack(spacing: 2) {
            Text(dart?.hit.label ?? "–")
                .font(.dvNumber(26, weight: .heavy))
                .contentTransition(.numericText())
            Text(subtitle)
                .font(.dvRounded(12, weight: .medium))
                .foregroundStyle(Color.dvTextSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 68)
        .foregroundStyle(dart == nil ? Color.dvTextTertiary : Color.dvText)
        .background(Color.dvSurfaceRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(borderColor, style: StrokeStyle(lineWidth: 1.5, dash: dart?.isUncertain == true ? [5, 4] : []))
        )
        .overlay(alignment: .topTrailing) {
            if dart?.isUncertain == true {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFF9F43))
                    .padding(6)
            } else if dart?.source == .corrected || dart?.source == .manual {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.dvTextTertiary)
                    .padding(7)
            }
        }
        .animation(.snappy(duration: 0.25), value: dart?.hit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dart \(index + 1): \(dart?.hit.spokenText ?? "noch nicht geworfen")")
    }

    private var subtitle: String {
        guard let dart else { return "Dart \(index + 1)" }
        if dart.source == .autoMiss { return "nicht erkannt" }
        return "\(dart.hit.points) Pkt."
    }

    private var borderColor: Color {
        if dart?.isUncertain == true { return Color(hex: 0xFF9F43) }
        if dart != nil { return Color.dvGold.opacity(0.55) }
        return isNext ? Color.dvRed.opacity(0.7) : Color.dvStroke
    }
}

/// Spielerkarte im Scoreboard.
struct PlayerScoreCard: View {
    let name: String
    let remaining: Int
    let stats: PlayerStats
    let showLegs: Bool
    let isActive: Bool
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isActive ? Color.dvRed : Color.dvTextTertiary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(name)
                    .font(.dvRounded(15, weight: .semibold))
                    .foregroundStyle(isActive ? Color.dvText : Color.dvTextSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if showLegs {
                    Text("\(stats.legsWon)")
                        .font(.dvNumber(13, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.dvSurfaceRaised, in: Capsule())
                        .foregroundStyle(Color.dvGold)
                        .accessibilityLabel("\(stats.legsWon) Legs")
                }
            }
            Text("\(remaining)")
                .font(.dvNumber(compact ? 34 : 46, weight: .heavy))
                .foregroundStyle(isActive ? Color.dvText : Color.dvTextSecondary)
                .contentTransition(.numericText(value: Double(remaining)))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack {
                Label(String(format: "%.1f", stats.threeDartAverage), systemImage: "chart.line.uptrend.xyaxis")
                Spacer(minLength: 4)
                Text("\(stats.darts) Darts")
            }
            .font(.dvRounded(12, weight: .medium))
            .foregroundStyle(Color.dvTextTertiary)
            .labelStyle(.titleAndIcon)
        }
        .dvCard(padding: compact ? 12 : 14, highlighted: isActive)
        .animation(.snappy(duration: 0.3), value: remaining)
        .animation(.easeInOut(duration: 0.25), value: isActive)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), Rest \(remaining), Schnitt \(String(format: "%.1f", stats.threeDartAverage))")
    }
}

/// Eingabefeld für Treffer (manuelles Spiel und Korrektur).
struct HitKeypad: View {
    let onHit: (Hit) -> Void
    @State private var multiplier = 1

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        VStack(spacing: 8) {
            ChipPicker(options: [1, 2, 3], selection: $multiplier) { value in
                switch value {
                case 2: return "Double"
                case 3: return "Triple"
                default: return "Single"
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(1...20, id: \.self) { number in
                    key("\(number)", tint: tint) { emit(number) }
                }
            }
            HStack(spacing: 6) {
                key("25", tint: .dvGreen) {
                    onHit(multiplier == 2 ? .bull : .outerBull)
                    multiplier = 1
                }
                key("Bull", tint: .dvRed) {
                    onHit(.bull)
                    multiplier = 1
                }
                key("Miss", tint: .dvTextSecondary) {
                    onHit(.miss)
                    multiplier = 1
                }
            }
        }
    }

    private var tint: Color {
        switch multiplier {
        case 2: return .dvGreen
        case 3: return .dvRed
        default: return .dvText
        }
    }

    private func emit(_ number: Int) {
        let hit: Hit
        switch multiplier {
        case 2: hit = .double(number)
        case 3: hit = .triple(number)
        default: hit = .single(number)
        }
        onHit(hit)
        multiplier = 1
    }

    private func key(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.dvNumber(19, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .foregroundStyle(tint)
                .background(Color.dvSurfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(KeyPressStyle())
    }
}

private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
