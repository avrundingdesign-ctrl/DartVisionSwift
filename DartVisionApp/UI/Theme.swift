import SwiftUI
import CoreText
import Foundation
import CoreGraphics

// MARK: - Farben ("Arena": dunkel, Akzente in Dartboard-Farben)

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    static let dvBackground = Color(hex: 0x0A0C0F)
    static let dvSurface = Color(hex: 0x12151A)
    static let dvSurfaceRaised = Color(hex: 0x1A1E25)
    static let dvStroke = Color.white.opacity(0.07)
    static let dvText = Color(hex: 0xF3EFE6)
    static let dvTextSecondary = Color(hex: 0xA0A7B1)
    /// Hell genug für Fließtext (Kontrast ≥ 4,5:1 auf Hintergrund und Karten).
    static let dvTextTertiary = Color(hex: 0x7C838E)
    static let dvRed = Color(hex: 0xE63946)
    static let dvGreen = Color(hex: 0x2BB673)
    static let dvGold = Color(hex: 0xF2B84B)
    static let dvCream = Color(hex: 0xEADFC4)
    static let dvBoardBlack = Color(hex: 0x16181B)
}

// MARK: - Typografie

extension Font {
    /// Große Zahlen: gerundet, gleich breite Ziffern (springen beim Hochzählen nicht).
    static func dvNumber(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static func dvRounded(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func dvWordmark(_ size: CGFloat) -> Font {
        .custom("Italiana-Regular", size: size)
    }
}

enum AppFonts {
    /// Registriert die mitgelieferte Schrift (ohne Info.plist-Eintrag).
    static func register() {
        guard let url = Bundle.main.url(forResource: "Italiana-Regular", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

// MARK: - Bausteine

struct DVButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case subtle
        case destructive
    }

    var kind: Kind = .primary
    var height: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, kind: kind, height: height)
    }

    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let height: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.dvRounded(17, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: height)
                .padding(.horizontal, 12)
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(kind == .primary ? Color.clear : Color.dvStroke, lineWidth: 1)
                )
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }

        private var foreground: Color {
            switch kind {
            case .primary: return .white
            case .secondary, .subtle: return .dvText
            case .destructive: return .dvRed
            }
        }

        private var background: Color {
            switch kind {
            case .primary: return .dvRed
            case .secondary: return .dvSurfaceRaised
            case .subtle: return .dvSurface
            case .destructive: return Color.dvRed.opacity(0.12)
            }
        }
    }
}

struct DVCardModifier: ViewModifier {
    var padding: CGFloat = 16
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.dvSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(highlighted ? Color.dvRed.opacity(0.85) : Color.dvStroke,
                                  lineWidth: highlighted ? 1.5 : 1)
            )
            .shadow(color: highlighted ? Color.dvRed.opacity(0.25) : .clear, radius: 18, y: 6)
    }
}

extension View {
    func dvCard(padding: CGFloat = 16, highlighted: Bool = false) -> some View {
        modifier(DVCardModifier(padding: padding, highlighted: highlighted))
    }
}

/// Überschrift über einem Abschnitt.
struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.dvRounded(12, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Color.dvTextTertiary)
    }
}

/// Segment-Auswahl als Chips.
struct ChipPicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.dvRounded(15, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .foregroundStyle(isSelected ? Color.dvBackground : Color.dvText)
                        .background(isSelected ? Color.dvCream : Color.dvSurfaceRaised,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: isSelected)
            }
        }
    }
}

/// Kleiner Status-Hinweis (z. B. "KI beobachtet").
struct StatusPill: View {
    let text: String
    let systemImage: String
    let tint: Color
    var pulsing = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .symbolEffect(.pulse, isActive: pulsing)
            Text(text)
                .lineLimit(1)
        }
        .font(.dvRounded(13, weight: .semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: Capsule())
    }
}
