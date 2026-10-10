import SwiftUI
import Foundation
import CoreGraphics

struct BoardMarker: Identifiable, Equatable {
    enum Style: Equatable {
        case current
        case previous
        case uncertain
        case pending
    }

    let id: UUID
    let position: CGPoint
    let label: String
    let style: Style
}

/// Vektor-Dartboard mit Treffer-Markierungen. Optional antippbar (liefert Board-Koordinaten in mm).
struct DartboardView: View {
    var markers: [BoardMarker] = []
    var highlight: Hit?
    var onTap: ((CGPoint) -> Void)?

    /// Außenradius der Zeichnung inkl. Zahlenring (mm).
    static let drawingRadius: Double = 226

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let scale = side / 2 / Self.drawingRadius
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                Canvas { context, _ in
                    Self.drawBoard(in: &context, center: center, scale: scale, highlight: highlight)
                }
                ForEach(markers) { marker in
                    MarkerDot(marker: marker)
                        .position(Self.viewPoint(marker.position, center: center, scale: scale))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard let onTap else { return }
                onTap(CGPoint(x: (location.x - center.x) / scale, y: -(location.y - center.y) / scale))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: markers)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dartboard")
        .accessibilityValue(markers.map(\.label).joined(separator: ", "))
    }

    static func viewPoint(_ board: CGPoint, center: CGPoint, scale: Double) -> CGPoint {
        CGPoint(x: center.x + board.x * scale, y: center.y - board.y * scale)
    }

    // MARK: - Zeichnen

    private static func drawBoard(in context: inout GraphicsContext, center: CGPoint, scale: Double, highlight: Hit?) {
        func p(_ radius: Double, _ angle: Double) -> CGPoint {
            viewPoint(BoardGeometry.point(radius: radius, angleDegrees: angle), center: center, scale: scale)
        }

        func sector(_ r0: Double, _ r1: Double, _ a0: Double, _ a1: Double) -> Path {
            var path = Path()
            let steps = 8
            path.move(to: p(r1, a0))
            for i in 1...steps {
                path.addLine(to: p(r1, a0 + (a1 - a0) * Double(i) / Double(steps)))
            }
            for i in stride(from: steps, through: 0, by: -1) {
                path.addLine(to: p(r0, a0 + (a1 - a0) * Double(i) / Double(steps)))
            }
            path.closeSubpath()
            return path
        }

        func circle(_ radius: Double) -> Path {
            let r = radius * scale
            return Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        }

        let g = BoardGeometry.self
        context.fill(circle(drawingRadius), with: .color(.dvBoardBlack))
        context.stroke(circle(drawingRadius), with: .color(Color.white.opacity(0.08)), lineWidth: 1)

        for (index, number) in g.numbers.enumerated() {
            let a0 = Double(index) * 18 - 9
            let a1 = a0 + 18
            let dark = index % 2 == 0
            let single = dark ? Color(hex: 0x1F2124) : Color.dvCream
            let ring = dark ? Color.dvRed : Color.dvGreen
            context.fill(sector(g.outerBullRadius, g.trebleInnerRadius, a0, a1), with: .color(single))
            context.fill(sector(g.trebleInnerRadius, g.trebleOuterRadius, a0, a1), with: .color(ring))
            context.fill(sector(g.trebleOuterRadius, g.doubleInnerRadius, a0, a1), with: .color(single))
            context.fill(sector(g.doubleInnerRadius, g.doubleOuterRadius, a0, a1), with: .color(ring))

            let label = Text("\(number)")
                .font(.system(size: max(9, 19 * scale), weight: .bold, design: .rounded))
                .foregroundColor(Color.dvText.opacity(0.85))
            context.draw(label, at: p(198, Double(index) * 18))
        }

        context.fill(circle(g.outerBullRadius), with: .color(.dvGreen))
        context.fill(circle(g.innerBullRadius), with: .color(.dvRed))

        // Drähte
        let wire = GraphicsContext.Shading.color(Color.white.opacity(0.22))
        for radius in g.ringRadii {
            context.stroke(circle(radius), with: wire, lineWidth: 0.7)
        }
        for index in 0..<20 {
            var line = Path()
            let angle = Double(index) * 18 - 9
            line.move(to: p(g.outerBullRadius, angle))
            line.addLine(to: p(g.doubleOuterRadius, angle))
            context.stroke(line, with: wire, lineWidth: 0.7)
        }

        // Hervorgehobenes Feld (z. B. in der Korrektur)
        if let highlight {
            for path in highlightPaths(for: highlight, sector: sector, circle: circle) {
                context.fill(path, with: .color(Color.white.opacity(0.35)))
                context.stroke(path, with: .color(.white), lineWidth: 1.5)
            }
        }
    }

    private static func highlightPaths(for hit: Hit,
                                       sector: (Double, Double, Double, Double) -> Path,
                                       circle: (Double) -> Path) -> [Path] {
        let g = BoardGeometry.self
        switch hit.ring {
        case .miss:
            return []
        case .bull:
            return [circle(g.innerBullRadius)]
        case .outerBull:
            return [circle(g.outerBullRadius)]
        case .single, .double, .triple:
            guard let center = g.centerAngle(of: hit.number) else { return [] }
            let a0 = center - 9, a1 = center + 9
            switch hit.ring {
            case .triple: return [sector(g.trebleInnerRadius, g.trebleOuterRadius, a0, a1)]
            case .double: return [sector(g.doubleInnerRadius, g.doubleOuterRadius, a0, a1)]
            default:
                return [sector(g.outerBullRadius, g.trebleInnerRadius, a0, a1),
                        sector(g.trebleOuterRadius, g.doubleInnerRadius, a0, a1)]
            }
        }
    }
}

private struct MarkerDot: View {
    let marker: BoardMarker

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            Circle()
                .strokeBorder(Color.white, style: StrokeStyle(lineWidth: 2, dash: marker.style == .uncertain ? [3, 2] : []))
                .frame(width: 20, height: 20)
            Text(marker.label)
                .font(.dvRounded(10, weight: .heavy))
                .foregroundStyle(Color.dvBackground)
        }
        .opacity(marker.style == .pending ? 0.55 : 1)
    }

    private var fill: Color {
        switch marker.style {
        case .current: return .dvGold
        case .previous: return .dvCream
        case .uncertain: return Color(hex: 0xFF9F43)
        case .pending: return .white
        }
    }
}
