import Foundation
import UIKit

// MARK: - Pipeline-Test

/// Testet die On-Device-Pipeline gegen Python-Referenzdaten.
/// Kann als Unit Test oder als Debug-Aufruf in der App verwendet werden.
struct PipelineTest {

    // Referenzdaten aus Python (test_reference_data.json)
    // Format: Bild → erwartete Dart-Scores
    struct ExpectedResult {
        let image: String
        let expectedDarts: [(rawX: CGFloat, rawY: CGFloat, boardX: Int, boardY: Int, score: Int, fieldType: String)]
        let keypoints: [String: CGPoint]  // TOP, Right, Bottom, Left
    }

    /// Referenzdaten aus der Python-Pipeline
    static let referenceData: [ExpectedResult] = [
        ExpectedResult(
            image: "original_20260112_144855_218934",
            expectedDarts: [
                (672.2, 850.3, 292, 153, 4, "single"),
                (377.6, 570.3, 186,  47, 20, "single"),
                (347.9, 557.6, 173,  40, 5, "single")
            ],
            keypoints: [
                "TOP":    CGPoint(x: 336.88, y: 455.85),
                "Right":  CGPoint(x: 598.00, y: 804.00),
                "Bottom": CGPoint(x: 333.00, y: 1157.00),
                "Left":   CGPoint(x: 71.48, y: 1157.43)
            ]
        ),
        ExpectedResult(
            image: "original_20260112_144914_885829",
            expectedDarts: [
                (442.7, 743.4, 210, 108, 20, "single"),
                (597.9, 513.3, 274,  53, 1, "single")
            ],
            keypoints: [
                "TOP":    CGPoint(x: 336.88, y: 455.85),
                "Right":  CGPoint(x: 598.00, y: 804.00),
                "Bottom": CGPoint(x: 333.00, y: 1157.00),
                "Left":   CGPoint(x: 71.48, y: 1157.43)
            ]
        ),
        ExpectedResult(
            image: "original_20260112_144948_071977",
            expectedDarts: [
                (703.0, 605.2, 307, 88, 18, "single"),
                (441.0, 742.9, 209, 107, 20, "single")
            ],
            keypoints: [
                "TOP":    CGPoint(x: 336.88, y: 455.85),
                "Right":  CGPoint(x: 598.00, y: 804.00),
                "Bottom": CGPoint(x: 333.00, y: 1157.00),
                "Left":   CGPoint(x: 71.48, y: 1157.43)
            ]
        )
    ]

    // MARK: - DartScorer-Only Test (kein ML nötig)

    /// Testet nur den DartScorer mit bekannten Board-Koordinaten.
    /// Kann sofort ohne Modelle/Bilder laufen.
    static func testDartScorer() -> Bool {
        print("🧪 === DartScorer Test ===")
        var allPassed = true

        let tests: [(name: String, x: CGFloat, y: CGFloat, expectedScore: Int, expectedType: String)] = [
            ("Bullseye",       200, 200, 50, "bull"),
            ("Outer Bull",     200, 190, 25, "outer_bull"),
            ("Triple 20",      200,  79, 60, "triple"),
            ("Double 20",      200,   5, 40, "double"),
            ("Single 20",      200, 150, 20, "single"),
            ("Miss",             0,   0,  0, "miss"),

            // Referenzdaten aus Python-Pipeline
            ("Board (292,153)", 292, 153,  4, "single"),
            ("Board (186,47)",  186,  47, 20, "single"),
            ("Board (210,108)", 210, 108, 20, "single"),
            ("Board (274,53)",  274,  53,  1, "single"),
            ("Board (307,88)",  307,  88, 18, "single"),
            ("Board (209,107)", 209, 107, 20, "single"),
        ]

        for test in tests {
            let result = DartScorer.getScore(at: CGPoint(x: test.x, y: test.y))
            let passed = result.value == test.expectedScore
            let icon = passed ? "✅" : "❌"
            print("  \(icon) \(test.name): (\(Int(test.x)),\(Int(test.y))) → score=\(result.value) (\(result.fieldType)) [erwartet: \(test.expectedScore) (\(test.expectedType))]")
            if !passed { allPassed = false }
        }

        print(allPassed ? "  ✅ Alle DartScorer Tests bestanden!" : "  ❌ Einige Tests fehlgeschlagen!")
        return allPassed
    }

    // MARK: - Homographie Test (kein ML nötig)

    /// Testet die Homographie + Transformation mit bekannten Keypoints und Dart-Positionen.
    static func testHomography() -> Bool {
        print("🧪 === Homographie Test ===")
        var allPassed = true

        // Keypoints aus Referenzdaten
        let keypoints: [DetectedKeypoint] = [
            DetectedKeypoint(label: "TOP",    point: CGPoint(x: 336.88, y: 455.85), confidence: 0.9),
            DetectedKeypoint(label: "Right",  point: CGPoint(x: 598.00, y: 804.00), confidence: 0.9),
            DetectedKeypoint(label: "Bottom", point: CGPoint(x: 333.00, y: 1157.00), confidence: 0.9),
            DetectedKeypoint(label: "Left",   point: CGPoint(x: 71.48,  y: 1157.43), confidence: 0.9),
        ]

        guard let H = BoardWarper.computeHomography(from: keypoints) else {
            print("  ❌ Homographie-Berechnung fehlgeschlagen")
            return false
        }
        print("  ✅ Homographie berechnet: [\(H.map { String(format: "%.6f", $0) }.joined(separator: ", "))]")

        // Dart-Punkte transformieren und mit Python-Referenz vergleichen
        let tests: [(rawX: CGFloat, rawY: CGFloat, expectedBoardX: Int, expectedBoardY: Int)] = [
            (672.2, 850.3, 292, 153),
            (377.6, 570.3, 186,  47),
            (347.9, 557.6, 173,  40),
            (442.7, 743.4, 210, 108),
            (597.9, 513.3, 274,  53),
            (703.0, 605.2, 307,  88),
            (441.0, 742.9, 209, 107),
        ]

        let tolerance: CGFloat = 5.0  // ±5 Pixel Toleranz

        for test in tests {
            let raw = CGPoint(x: test.rawX, y: test.rawY)
            let board = BoardWarper.transformPoint(raw, homography: H)
            let dx = abs(board.x - CGFloat(test.expectedBoardX))
            let dy = abs(board.y - CGFloat(test.expectedBoardY))
            let passed = dx <= tolerance && dy <= tolerance
            let icon = passed ? "✅" : "❌"
            print("  \(icon) (\(test.rawX),\(test.rawY)) → (\(Int(board.x)),\(Int(board.y))) [erwartet: (\(test.expectedBoardX),\(test.expectedBoardY)), Δ=(\(String(format: "%.1f", dx)),\(String(format: "%.1f", dy)))]")
            if !passed { allPassed = false }
        }

        print(allPassed ? "  ✅ Alle Homographie Tests bestanden!" : "  ❌ Einige Tests fehlgeschlagen!")
        return allPassed
    }

    // MARK: - Full Pipeline Test (ML + Bilder nötig)

    /// Testet die komplette Pipeline mit echten Testbildern.
    /// Benötigt: Testbilder in der App-Bundle + CoreML-Modelle.
    static func testFullPipeline() {
        print("🧪 === Full Pipeline Test ===")

        do {
            let pipeline = try ImagePipeline()

            for ref in referenceData {
                guard let path = Bundle.main.path(forResource: ref.image, ofType: "jpg"),
                      let uiImage = UIImage(contentsOfFile: path),
                      let cgImage = uiImage.cgImage else {
                    print("  ⚠️ Bild \(ref.image).jpg nicht gefunden")
                    continue
                }

                let result = try pipeline.process(image: cgImage)

                print("  📸 \(ref.image):")
                print("    Keypoints: \(result.keypoints.count)")
                print("    Darts: \(result.darts.count) (erwartet: \(ref.expectedDarts.count))")

                for (i, dart) in result.darts.enumerated() {
                    let expected = i < ref.expectedDarts.count ? ref.expectedDarts[i] : nil
                    print("    Dart \(i+1): board=(\(Int(dart.position.x)),\(Int(dart.position.y))) score=\(dart.score.value) (\(dart.score.fieldType)) conf=\(String(format: "%.3f", dart.confidence))")
                    if let exp = expected {
                        print("      erwartet: board=(\(exp.boardX),\(exp.boardY)) score=\(exp.score) (\(exp.fieldType))")
                    }
                }
            }
        } catch {
            print("  ❌ Pipeline-Fehler: \(error.localizedDescription)")
        }
    }

    // MARK: - Alle Tests

    /// Führt alle verfügbaren Tests aus.
    static func runAll() {
        print("🧪 ════════════════════════════════════")
        print("🧪  DartVision Pipeline Tests")
        print("🧪 ════════════════════════════════════")
        print()

        let scorerOK = testDartScorer()
        print()

        let homoOK = testHomography()
        print()

        // Full Pipeline nur wenn Scorer + Homographie OK
        if scorerOK && homoOK {
            testFullPipeline()
        } else {
            print("⚠️ Full Pipeline Test übersprungen (vorherige Tests fehlgeschlagen)")
        }

        print()
        print("🧪 ════════════════════════════════════")
        print("🧪  Tests abgeschlossen")
        print("🧪 ════════════════════════════════════")
    }
}
