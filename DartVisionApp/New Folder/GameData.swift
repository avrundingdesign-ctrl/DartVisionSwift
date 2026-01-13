import Foundation
import CoreGraphics

// 1. ✅ Das fehlende Enum "GameMode" definieren
enum GameMode: String, CaseIterable, Identifiable {
    case x301 = "301"
    case x501 = "501"
    case x10 = "10"
    case followMe = "Follow Me"
    
    var id: String { self.rawValue }
}

// 2. Das Keypoints Struct (bleibt wie es war)
struct Keypoints {
    var top: CGPoint
    var right: CGPoint
    var bottom: CGPoint
    var left: CGPoint
}

// 3. GameData erweitern
struct GameData {
    // ✅ NEU: Die Variable für den Spielmodus hinzufügen
    var mode: GameMode = .x301
    
    // Der Rest bleibt gleich
    var keypoints: Keypoints? = nil
    var detectedDarts: [DartData] = []
    var dartScores: [Int] = []
}
