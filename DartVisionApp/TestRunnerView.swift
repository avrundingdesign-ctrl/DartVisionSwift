import SwiftUI

// MARK: - Test Runner View

/// Debug-View zum Testen der On-Device-Pipeline gegen Python-Referenzdaten.
/// Zeigt Board-Keypoints, Dart-Positionen und Scores verglichen mit Python.
struct TestRunnerView: View {

    @State private var testResults: [ImageTestResult] = []
    @State private var isRunning = false
    @State private var statusText = "Bereit"
    @State private var scorerTestLog: [String] = []
    @State private var homoTestLog: [String] = []

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── Run Button ──
                    Button(action: runAllTests) {
                        HStack {
                            Image(systemName: isRunning ? "hourglass" : "play.fill")
                            Text(isRunning ? "Tests laufen..." : "Pipeline Tests starten")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isRunning ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isRunning)

                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // ── DartScorer Tests ──
                    if !scorerTestLog.isEmpty {
                        sectionHeader("🎯 DartScorer Tests")
                        ForEach(scorerTestLog, id: \.self) { line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }

                    // ── Homographie Tests ──
                    if !homoTestLog.isEmpty {
                        sectionHeader("📐 Homographie Tests")
                        ForEach(homoTestLog, id: \.self) { line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }

                    // ── Full Pipeline Results ──
                    if !testResults.isEmpty {
                        sectionHeader("🧪 Full Pipeline vs Python")

                        ForEach(testResults) { result in
                            imageResultCard(result)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Pipeline Tests")
        }
    }

    // MARK: - UI Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.top, 8)
    }

    private func imageResultCard(_ result: ImageTestResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Bildname + Status
            HStack {
                Text(result.imageName)
                    .font(.system(.subheadline, design: .monospaced))
                    .bold()
                Spacer()
                Text(result.allMatch ? "✅ MATCH" : "❌ MISMATCH")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(result.allMatch ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    .cornerRadius(4)
            }

            // Keypoints
            if !result.keypoints.isEmpty {
                Text("Board-Keypoints: \(result.keypoints.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Dart-Vergleich
            if result.swiftDarts.isEmpty && result.pythonDarts.isEmpty {
                Text("Keine Darts erkannt (korrekt)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                // Header
                HStack {
                    Text("").frame(width: 50)
                    Text("Swift").frame(width: 80).bold()
                    Text("Python").frame(width: 80).bold()
                    Text("").frame(width: 30)
                }
                .font(.caption2)

                // Swift Darts
                let maxCount = max(result.swiftDarts.count, result.pythonDarts.count)
                ForEach(0..<maxCount, id: \.self) { i in
                    HStack {
                        Text("Dart \(i+1)")
                            .frame(width: 50, alignment: .leading)

                        // Swift
                        if i < result.swiftDarts.count {
                            let d = result.swiftDarts[i]
                            Text("\(d.score) \(d.fieldType)")
                                .frame(width: 80)
                        } else {
                            Text("—").frame(width: 80)
                        }

                        // Python
                        if i < result.pythonDarts.count {
                            let d = result.pythonDarts[i]
                            Text("\(d.score) \(d.fieldType)")
                                .frame(width: 80)
                        } else {
                            Text("—").frame(width: 80)
                        }

                        // Match indicator
                        if i < result.swiftDarts.count && i < result.pythonDarts.count {
                            let match = result.swiftDarts[i].score == result.pythonDarts[i].score
                            Text(match ? "✅" : "❌").frame(width: 30)
                        } else {
                            Text("⚠️").frame(width: 30)
                        }
                    }
                    .font(.system(.caption, design: .monospaced))
                }
            }

            if let error = result.error {
                Text("❌ \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Test Logic

    private func runAllTests() {
        isRunning = true
        statusText = "Tests laufen..."
        testResults = []
        scorerTestLog = []
        homoTestLog = []

        DispatchQueue.global(qos: .userInitiated).async {
            // ─── 1. DartScorer Test ───
            let scorerResults = runDartScorerTests()
            DispatchQueue.main.async { scorerTestLog = scorerResults }

            // ─── 2. Homographie Test ───
            let homoResults = runHomographyTests()
            DispatchQueue.main.async { homoTestLog = homoResults }

            // ─── 3. Full Pipeline Test ───
            let pipelineResults = runFullPipelineTests()
            DispatchQueue.main.async {
                testResults = pipelineResults
                isRunning = false
                let matched = pipelineResults.filter { $0.allMatch }.count
                statusText = "Fertig: \(matched)/\(pipelineResults.count) Bilder stimmen überein"
            }
        }
    }

    // MARK: - DartScorer Tests

    private func runDartScorerTests() -> [String] {
        var log: [String] = []

        let tests: [(name: String, x: CGFloat, y: CGFloat, score: Int, fieldType: String)] = [
            ("Bullseye",       200, 200, 50, "bull"),
            ("Outer Bull",     200, 190, 25, "outer_bull"),
            ("Triple 20",      200,  79, 60, "triple"),
            ("Double 20",      200,   5, 40, "double"),
            ("Single 20",      200, 150, 20, "single"),
            ("Miss",             0,   0,  0, "miss"),
            // Python-Referenzpunkte
            ("Ref (292,153)",  292, 153,  4, "single"),
            ("Ref (186,47)",   186,  47, 20, "single"),
            ("Ref (173,40)",   173,  40,  5, "single"),
            ("Ref (210,108)",  210, 108, 20, "single"),
            ("Ref (274,53)",   274,  53,  1, "single"),
            ("Ref (307,88)",   307,  88, 18, "single"),
            ("Ref (209,107)",  209, 107, 20, "single"),
        ]

        for t in tests {
            let result = DartScorer.getScore(at: CGPoint(x: t.x, y: t.y))
            let ok = result.value == t.score
            log.append("\(ok ? "✅" : "❌") \(t.name): \(result.value) (\(result.fieldType)) [erwartet: \(t.score)]")
        }

        return log
    }

    // MARK: - Homographie Tests

    private func runHomographyTests() -> [String] {
        var log: [String] = []

        // Echte Keypoints aus Python-Referenz (Bild 144855)
        let keypoints: [DetectedKeypoint] = [
            DetectedKeypoint(label: "TOP",    point: CGPoint(x: 333.01, y: 451.44), confidence: 0.9),
            DetectedKeypoint(label: "Right",  point: CGPoint(x: 1062.45, y: 853.81), confidence: 0.9),
            DetectedKeypoint(label: "Bottom", point: CGPoint(x: 553.78, y: 1738.68), confidence: 0.9),
            DetectedKeypoint(label: "Left",   point: CGPoint(x: 69.70, y: 1154.95), confidence: 0.9),
        ]

        guard let H = BoardWarper.computeHomography(from: keypoints) else {
            log.append("❌ Homographie fehlgeschlagen")
            return log
        }
        log.append("✅ Homographie berechnet")

        // Dart-Punkte aus dem gleichen Bild (144855) transformieren
        let tests: [(rawX: CGFloat, rawY: CGFloat, boardX: Int, boardY: Int, score: Int)] = [
            (672.17, 850.34, 292, 153, 4),
            (377.56, 570.34, 186,  47, 20),
            (347.88, 557.61, 173,  40, 5),
        ]

        let tolerance: CGFloat = 5.0

        for t in tests {
            let board = BoardWarper.transformPoint(CGPoint(x: t.rawX, y: t.rawY), homography: H)
            let dx = abs(board.x - CGFloat(t.boardX))
            let dy = abs(board.y - CGFloat(t.boardY))
            let ok = dx <= tolerance && dy <= tolerance
            log.append("\(ok ? "✅" : "❌") (\(Int(t.rawX)),\(Int(t.rawY))) → (\(Int(board.x)),\(Int(board.y))) [erw: (\(t.boardX),\(t.boardY)) Δ=\(String(format: "%.1f,%.1f", dx, dy))]")

            // Score auch prüfen
            let score = DartScorer.getScore(at: board)
            let scoreOK = score.value == t.score
            log.append("   \(scoreOK ? "✅" : "❌") Score: \(score.value) [erwartet: \(t.score)]")
        }

        return log
    }

    // MARK: - Full Pipeline

    /// Python-Referenzdaten für den Vergleich
    private struct PythonRef {
        let image: String
        let darts: [(score: Int, fieldType: String)]
    }

    private static let pythonReference: [PythonRef] = [
        PythonRef(image: "original_20260112_144855_218934", darts: [
            (score: 4,  fieldType: "single"),
            (score: 20, fieldType: "single"),
            (score: 5,  fieldType: "single"),
        ]),
        PythonRef(image: "original_20260112_144914_885829", darts: [
            (score: 20, fieldType: "single"),
            (score: 1,  fieldType: "single"),
        ]),
        PythonRef(image: "original_20260112_144948_071977", darts: [
            (score: 18, fieldType: "single"),
            (score: 20, fieldType: "single"),
        ]),
    ]

    private func runFullPipelineTests() -> [ImageTestResult] {
        var results: [ImageTestResult] = []

        do {
            let pipeline = try ImagePipeline()

            for ref in Self.pythonReference {
                var result = ImageTestResult(imageName: ref.image)
                result.pythonDarts = ref.darts.map { DartResult(score: $0.score, fieldType: $0.fieldType) }

                // Bild laden
                guard let path = Bundle.main.path(forResource: ref.image, ofType: "jpg"),
                      let uiImage = UIImage(contentsOfFile: path),
                      let cgImage = uiImage.cgImage else {
                    result.error = "Bild nicht im Bundle gefunden"
                    results.append(result)
                    continue
                }

                // Pipeline ausführen
                let pipelineResult = try pipeline.process(image: cgImage)
                pipeline.resetKeypoints()  // Für jedes Bild frische Keypoints

                result.keypoints = pipelineResult.keypoints.map { $0.label }

                // Swift-Ergebnisse
                result.swiftDarts = pipelineResult.darts.map {
                    DartResult(score: $0.score.value, fieldType: $0.score.fieldType)
                }

                // Scores vergleichen (Reihenfolge kann anders sein, deshalb sortieren)
                let swiftScores = result.swiftDarts.map { $0.score }.sorted()
                let pythonScores = result.pythonDarts.map { $0.score }.sorted()
                result.allMatch = (swiftScores == pythonScores) && (result.swiftDarts.count == result.pythonDarts.count)

                results.append(result)
            }
        } catch {
            results.append(ImageTestResult(
                imageName: "PIPELINE ERROR",
                error: error.localizedDescription
            ))
        }

        return results
    }
}

// MARK: - Datenmodelle für Test-Ergebnisse

struct DartResult: Identifiable {
    let id = UUID()
    let score: Int
    let fieldType: String
}

struct ImageTestResult: Identifiable {
    let id = UUID()
    let imageName: String
    var keypoints: [String] = []
    var swiftDarts: [DartResult] = []
    var pythonDarts: [DartResult] = []
    var allMatch: Bool = false
    var error: String? = nil

    init(imageName: String, error: String? = nil) {
        self.imageName = imageName
        self.error = error
    }
}

// MARK: - Preview

#Preview {
    TestRunnerView()
}
