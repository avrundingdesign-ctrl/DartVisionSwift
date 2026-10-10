import SwiftUI
import CoreImage
import Foundation
import CoreGraphics
import CoreVideo

/// Selbsttest der Logik und Vergleich der KI mit den Referenzbildern aus `TestData`.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var app
    @State private var selfTests: [SelfTest.Result] = []
    @State private var imageResults: [ImageTestResult] = []
    @State private var isRunning = false

    var body: some View {
        List {
            Section {
                let passed = selfTests.filter(\.passed).count
                LabeledContent("Ergebnis", value: "\(passed) / \(selfTests.count) bestanden")
                    .foregroundStyle(passed == selfTests.count ? Color.dvGreen : Color.dvRed)
                ForEach(selfTests) { result in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(result.passed ? Color.dvGreen : Color.dvRed)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.name)
                            Text(result.detail.isEmpty ? result.group : "\(result.group) – \(result.detail)")
                                .font(.caption)
                                .foregroundStyle(Color.dvTextSecondary)
                        }
                    }
                }
            } header: {
                Text("Selbsttest Spiellogik")
            }

            Section {
                Button {
                    Task { await runImageTests() }
                } label: {
                    HStack {
                        Label("Testbilder analysieren", systemImage: "photo.stack")
                        if isRunning {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isRunning)
                ForEach(imageResults) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: result.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(result.ok ? Color.dvGreen : Color.dvGold)
                            Text(result.title)
                                .font(.subheadline.weight(.semibold))
                        }
                        Text(result.detail)
                            .font(.caption.monospaced())
                            .foregroundStyle(Color.dvTextSecondary)
                    }
                }
            } header: {
                Text("KI-Testbilder")
            } footer: {
                Text("Vergleicht die aktuelle KI mit den Referenzwerten der Server-Pipeline (test_reference_data.json). Darts mit „⚠︎“ sitzen sehr nah am Draht.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.dvBackground)
        .navigationTitle("Diagnose")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selfTests.isEmpty { selfTests = SelfTest.runAll() }
        }
    }

    // MARK: - Testbilder

    struct ImageTestResult: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let ok: Bool
    }

    private struct ReferenceEntry: Decodable {
        let image: String
        let keypoints: [String: [Double]]
        let darts: [ReferenceDart]
    }

    private struct ReferenceDart: Decodable {
        let boardX: Double
        let boardY: Double
        let score: Int
        let fieldType: String
    }

    private func runImageTests() async {
        isRunning = true
        defer { isRunning = false }
        imageResults = []

        guard let detector = await app.makeDetector() else {
            imageResults = [ImageTestResult(title: "KI nicht verfügbar", detail: app.detectorError ?? "–", ok: false)]
            return
        }
        guard let url = Bundle.main.url(forResource: "test_reference_data", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            imageResults = [ImageTestResult(title: "Referenzdaten fehlen", detail: "test_reference_data.json", ok: false)]
            return
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let references = try? decoder.decode([ReferenceEntry].self, from: data) else {
            imageResults = [ImageTestResult(title: "Referenzdaten unlesbar", detail: "", ok: false)]
            return
        }

        var tested = 0
        for reference in references {
            let name = (reference.image as NSString).deletingPathExtension
            guard let imageURL = Bundle.main.url(forResource: name, withExtension: "jpg"),
                  let image = CIImage(contentsOf: imageURL, options: [.applyOrientationProperty: true]),
                  let buffer = FrameRenderer.shared.pixelBuffer(from: image)
            else { continue }
            tested += 1
            imageResults.append(await analyze(reference, buffer: buffer, detector: detector))
        }
        if tested == 0 {
            imageResults = [ImageTestResult(title: "Keine Testbilder im Bundle", detail: "TestData/*.jpg", ok: false)]
        }
    }

    private func analyze(_ reference: ReferenceEntry, buffer: CVPixelBuffer, detector: any DartDetector) async -> ImageTestResult {
        let frame = AnalysisFrame(pixelBuffer: buffer, timestamp: 0)
        let started = Date()
        var lines: [String] = []

        let expectedPoints = ["TOP", "Right", "Bottom", "Left"].compactMap { key -> CGPoint? in
            guard let pair = reference.keypoints[key], pair.count == 2 else { return nil }
            return CGPoint(x: pair[0], y: pair[1])
        }
        let expectedKeypoints = BoardKeypoints(points: expectedPoints)

        let board = try? await detector.detectBoard(in: frame)
        var usedKeypoints = board?.keypoints
        if let found = usedKeypoints, let expected = expectedKeypoints {
            lines.append(String(format: "Board: max. Abweichung %.1f px", Double(found.maxDistance(to: expected))))
        } else {
            lines.append("Board: nicht erkannt – nutze Referenzpunkte")
            usedKeypoints = expectedKeypoints
        }

        guard let keypoints = usedKeypoints,
              let calibration = BoardCalibration(keypoints: keypoints, imageSize: frame.size)
        else {
            return ImageTestResult(title: reference.image, detail: "Kalibrierung ungültig", ok: false)
        }

        let candidates = (try? await detector.detectDarts(in: frame, calibration: calibration)) ?? []
        let detected = candidates
            .filter { $0.confidence >= app.settings.minConfidence }
            .sorted { $0.confidence > $1.confidence }
        let detectedLabels = detected.map { candidate -> String in
            let hit = BoardGeometry.hit(at: candidate.boardPoint)
            let nearWire = BoardGeometry.wireDistance(at: candidate.boardPoint) < 1.5
            return hit.label + (nearWire ? "⚠︎" : "")
        }
        let expectedHits = reference.darts.map { dart -> Hit in
            let point = CGPoint(x: (dart.boardX - 200) * 0.85, y: (200 - dart.boardY) * 0.85)
            return BoardGeometry.hit(at: point)
        }
        let detectedHits = detected.map { BoardGeometry.hit(at: $0.boardPoint) }
        let sameScores = expectedHits.map(\.points).sorted() == detectedHits.map(\.points).sorted()

        lines.append("Erwartet: " + (expectedHits.isEmpty ? "–" : expectedHits.map(\.label).joined(separator: ", ")))
        lines.append("Erkannt:  " + (detectedLabels.isEmpty ? "–" : detectedLabels.joined(separator: ", ")))
        lines.append("Zeit: \(Int(Date().timeIntervalSince(started) * 1000)) ms (Board + Darts)")
        return ImageTestResult(title: reference.image, detail: lines.joined(separator: "\n"), ok: sameScores)
    }
}
