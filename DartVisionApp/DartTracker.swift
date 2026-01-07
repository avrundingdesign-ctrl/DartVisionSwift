import Foundation
import CoreGraphics

// 1. Das Enum definieren (außerhalb der Klasse)
enum ScanResult {
    case sameRound           // Bedeutet: "Warte, alte Runde noch aktiv"
    case update([DartData])  // Bedeutet: "Hier ist die neue Liste"
}

class DartTracker {
    
    private var history: [DartData] = []
    private let tolerance: CGFloat = 20.0
    private let maxDarts = 3
    var onScoresUpdated: (([Int]) -> Void)?
    
    // Rückgabetyp ist jetzt unser Enum "ScanResult"
    func merge(with newDarts: [DartData], isBusted: Bool) -> ScanResult {
        
        // ---------------------------------------------------------
        // SCHRITT 1: Check auf "Alte Runde"
        // ---------------------------------------------------------

        
        if history.count == maxDarts {
            
            // Prüfen: Gibt es eine Verbindung zu alten Darts?
            let connectionFound = newDarts.contains { newDart in
                history.contains { oldDart in
                    hypot(oldDart.x - newDart.x, oldDart.y - newDart.y) < tolerance
                }
            }
            
            // WENN Liste voll (3) UND alter Dart erkannt:
            // -> SOFORT ABBRECHEN und Signal "sameRound" senden.
            if connectionFound {
                return .sameRound
            }
            
            // Wenn wir hier ankommen, war die Liste voll, aber KEIN alter Dart da.
            // -> Das heißt: Pfeile wurden gezogen -> Reset.
            print("♻️ Reset: Neue Runde erkannt.")
            history.removeAll()
            onScoresUpdated?([])
        }
        
        // Spezialfall: Wenn isBusted gesetzt ist und wir alte Darts sehen
        // (Spieler hat bereits gebustet, Darts stecken noch)
        if isBusted && !history.isEmpty {
            let connectionFound = newDarts.contains { newDart in
                history.contains { oldDart in
                    hypot(oldDart.x - newDart.x, oldDart.y - newDart.y) < tolerance
                }
            }
            if connectionFound {
                return .sameRound
            }
        }
        
        // ---------------------------------------------------------
        // SCHRITT 2: Neue Darts hinzufügen (nur wenn oben nicht abgebrochen)
        // ---------------------------------------------------------
        for newDart in newDarts {
            // Stop, wenn voll
            if history.count >= maxDarts { break }
            
            // Stop, wenn Duplikat
            let isDuplicate = history.contains{ oldDart in
                hypot(oldDart.x - newDart.x, oldDart.y - newDart.y) < tolerance
            }
            if !isDuplicate {
                history.append(newDart)
                let currentScores = history.map { $0.score }
                onScoresUpdated?(currentScores)
            }
        }
        
        // Wir geben das Signal "update" mit der neuen Liste zurück
        return .update(history)
    }
    
    func reset() {
        history.removeAll()
        onScoresUpdated?([])
    }
}
