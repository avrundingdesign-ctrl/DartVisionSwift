import SwiftUI
import Foundation
import CoreGraphics

struct CalibrationView: View {
    @Environment(AppModel.self) private var app
    @State private var model: CalibrationModel?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                content(model)
            }
        }
        .onAppear {
            guard model == nil else { return }
            let created = CalibrationModel(app: app)
            model = created
            created.start()
        }
        .onDisappear { model?.stop() }
    }

    @ViewBuilder
    private func content(_ model: CalibrationModel) -> some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                if model.phase == .locked, let snapshot = model.snapshot, let keypoints = model.keypoints {
                    CalibrationEditor(image: snapshot, imageSize: model.imageSize, keypoints: keypoints,
                                      calibration: model.calibration) { index, point in
                        model.moveKeypoint(index, to: point)
                    }
                    .transition(.opacity)
                } else {
                    CameraPreviewView(camera: app.camera)
                        .overlay { AimingGuide() }
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(.easeInOut(duration: 0.3), value: model.phase)

            bottomPanel(model)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                app.cancelCalibration()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.dvText)
                    .frame(width: 40, height: 40)
                    .background(Color.dvSurface, in: Circle())
            }
            .accessibilityLabel("Abbrechen")
            Spacer()
            Text("Kalibrierung")
                .font(.dvRounded(17, weight: .bold))
                .foregroundStyle(Color.dvText)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.dvBackground)
    }

    @ViewBuilder
    private func bottomPanel(_ model: CalibrationModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            switch model.phase {
            case .starting:
                statusRow(icon: "camera", text: "Kamera wird gestartet …", tint: .dvTextSecondary, busy: true)
            case .searching(let message):
                statusRow(icon: "viewfinder", text: message, tint: .dvText, busy: true)
                ProgressView(value: model.progress)
                    .tint(.dvGreen)
                if app.camera.zoomOptions.count > 1 {
                    zoomPicker
                }
                Text("Tipp: Handy stabil und leicht seitlich statt genau frontal aufstellen (sonst verdecken Barrel und Flight die Spitze), ganzes Board im Bild, gleichmäßiges Licht – ideal ist ein LED-Ring.")
                    .font(.dvRounded(13, weight: .medium))
                    .foregroundStyle(Color.dvTextTertiary)
            case .locked:
                if let problem = model.problem {
                    statusRow(icon: "exclamationmark.triangle.fill", text: problem, tint: .dvGold, busy: false)
                } else {
                    statusRow(icon: "checkmark.seal.fill",
                              text: "Kalibriert. Ringe prüfen – Punkte lassen sich bei Bedarf verschieben.",
                              tint: .dvGreen, busy: false)
                }
                if let hint = model.qualityHint {
                    Label(hint.text, systemImage: hint.good ? "scope" : "exclamationmark.circle")
                        .font(.dvRounded(13, weight: .medium))
                        .foregroundStyle(hint.good ? Color.dvTextSecondary : Color.dvGold)
                }
                HStack(spacing: 10) {
                    Button {
                        model.retry()
                    } label: {
                        Label("Neu suchen", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(DVButtonStyle(kind: .secondary))
                    Button {
                        if let calibration = model.calibration {
                            app.calibrationFinished(calibration)
                        }
                    } label: {
                        Label("Spiel starten", systemImage: "play.fill")
                    }
                    .buttonStyle(DVButtonStyle(kind: .primary))
                    .disabled(model.calibration == nil)
                }
            case .failed(let message):
                statusRow(icon: "xmark.octagon.fill", text: message, tint: .dvRed, busy: false)
                Button {
                    model.retry()
                } label: {
                    Label("Erneut versuchen", systemImage: "arrow.clockwise")
                }
                .buttonStyle(DVButtonStyle(kind: .primary))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.dvBackground)
    }

    private var zoomPicker: some View {
        HStack(spacing: 8) {
            Text("Zoom")
                .font(.dvRounded(13, weight: .semibold))
                .foregroundStyle(Color.dvTextSecondary)
            ForEach(app.camera.zoomOptions, id: \.self) { option in
                let selected = abs(option - app.camera.zoom) < 0.01
                Button {
                    app.camera.setZoom(option)
                } label: {
                    Text(option == option.rounded() ? "\(Int(option))×" : String(format: "%.1f×", Double(option)))
                        .font(.dvNumber(14, weight: .bold))
                        .frame(width: 52, height: 34)
                        .foregroundStyle(selected ? Color.dvBackground : Color.dvText)
                        .background(selected ? Color.dvCream : Color.dvSurfaceRaised, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func statusRow(icon: String, text: String, tint: Color, busy: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .symbolEffect(.pulse, isActive: busy)
            Text(text)
                .font(.dvRounded(16, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
    }
}

/// Hilfslinien auf der Live-Vorschau.
private struct AimingGuide: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.72
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                    .frame(width: side, height: side)
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }
}

/// Standbild mit eingeblendeten Board-Ringen und verschiebbaren Kalibrierpunkten.
private struct CalibrationEditor: View {
    let image: CGImage
    let imageSize: CGSize
    let keypoints: BoardKeypoints
    let calibration: BoardCalibration?
    let onMove: (Int, CGPoint) -> Void

    @State private var dragOrigin: CGPoint?

    private static let labels = ["5 | 20", "13 | 6", "17 | 3", "8 | 11"]

    var body: some View {
        GeometryReader { geo in
            let fit = Self.fittedRect(container: geo.size, content: imageSize)
            let scale = fit.width / max(imageSize.width, 1)

            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: fit.width, height: fit.height)
                    .position(x: fit.midX, y: fit.midY)

                if let calibration {
                    Canvas { context, _ in
                        Self.drawRings(in: &context, calibration: calibration, fit: fit, scale: scale)
                    }
                    .allowsHitTesting(false)
                }

                ForEach(0..<4, id: \.self) { index in
                    let point = keypoints.points[index]
                    let viewPoint = CGPoint(x: fit.minX + point.x * scale, y: fit.minY + point.y * scale)
                    handle(label: Self.labels[index])
                        .position(viewPoint)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if dragOrigin == nil { dragOrigin = point }
                                    guard let origin = dragOrigin else { return }
                                    // Halbe Geschwindigkeit für pixelgenaues Feinjustieren.
                                    let moved = CGPoint(x: origin.x + value.translation.width / scale * 0.5,
                                                        y: origin.y + value.translation.height / scale * 0.5)
                                    onMove(index, moved)
                                }
                                .onEnded { _ in dragOrigin = nil }
                        )
                }
            }
        }
    }

    private func handle(label: String) -> some View {
        ZStack {
            Circle()
                .fill(Color.dvGold.opacity(0.25))
                .frame(width: 44, height: 44)
            Circle()
                .strokeBorder(Color.dvGold, lineWidth: 2)
                .frame(width: 44, height: 44)
            Circle()
                .fill(Color.dvGold)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.dvRounded(11, weight: .bold))
                .foregroundStyle(Color.dvBackground)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.dvGold, in: Capsule())
                .offset(y: -34)
        }
        .contentShape(Circle().inset(by: -8))
    }

    static func fittedRect(container: CGSize, content: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0 else { return CGRect(origin: .zero, size: container) }
        let scale = min(container.width / content.width, container.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private static func drawRings(in context: inout GraphicsContext, calibration: BoardCalibration, fit: CGRect, scale: CGFloat) {
        func view(_ boardPoint: CGPoint) -> CGPoint? {
            guard let p = calibration.imagePoint(fromBoard: boardPoint) else { return nil }
            return CGPoint(x: fit.minX + p.x * scale, y: fit.minY + p.y * scale)
        }

        var rings = Path()
        for radius in BoardGeometry.ringRadii {
            var started = false
            for step in 0...72 {
                guard let p = view(BoardGeometry.point(radius: radius, angleDegrees: Double(step) * 5)) else {
                    started = false
                    continue
                }
                if started { rings.addLine(to: p) } else { rings.move(to: p); started = true }
            }
        }
        for index in 0..<20 {
            let angle = Double(index) * 18 - 9
            if let a = view(BoardGeometry.point(radius: BoardGeometry.outerBullRadius, angleDegrees: angle)),
               let b = view(BoardGeometry.point(radius: BoardGeometry.doubleOuterRadius, angleDegrees: angle)) {
                rings.move(to: a)
                rings.addLine(to: b)
            }
        }
        context.stroke(rings, with: .color(Color.black.opacity(0.55)), lineWidth: 3)
        context.stroke(rings, with: .color(Color.dvGold), lineWidth: 1.2)

        for (index, number) in BoardGeometry.numbers.enumerated() {
            guard let p = view(BoardGeometry.point(radius: 192, angleDegrees: Double(index) * 18)) else { continue }
            let label = Text("\(number)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(Color.dvGold)
            context.draw(label, at: p)
        }
    }
}
