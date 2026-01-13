import Foundation
import CoreGraphics

// 1. Das Enum definieren (außerhalb der Klasse)
enum ScanResult {
    case sameRound           // Bedeutet: "Warte, alte Runde noch aktiv"
    case update([DartData])  // Bedeutet: "Hier ist die neue Liste"
}

class DartTracker {
    
    private var history: [DartData] = [] { didSet { print("📊 Aktuelle History: \(history.map { $0.score })") } }
    private var ignoredDarts: [DartData] = []  // Alte Pfeile vom vorherigen Spieler
    private let tolerance: CGFloat = 20.0
    private let maxDarts = 3
    var onScoresUpdated: (([Int]) -> Void)?
    
    // Rückgabetyp ist jetzt unser Enum "ScanResult"
    func merge(with newDarts: [DartData], isBusted: Bool) -> ScanResult {
        
        let historyOld = history
        
        // ---------------------------------------------------------
        // SCHRITT 1: Check auf "Alte Runde"
        // --------------------------------------------------------

        if newDarts.isEmpty && history.count == maxDarts {
            reset()
        }
        
        if history.count == maxDarts || isBusted { //geht das?
            
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
            history.removeAll()// Ignore-Liste auch leeren!
            onScoresUpdated?([])
            
        }
        
<<<<<<< HEAD
        let previousCount = history.count
=======
>>>>>>> NeuesteVersion
        
        // ---------------------------------------------------------
        // SCHRITT 2: Neue Darts hinzufügen (nur wenn oben nicht abgebrochen)
        // ---------------------------------------------------------
        for newDart in newDarts {
            // Stop, wenn voll
            
            
            if history.count >= maxDarts { break }
            
            // Prüfe ob dieser Dart ignoriert werden soll (alter Pfeil vom vorherigen Spieler)
            
            
            
            // DER ISIGNORED TEIL IST UNNÖTIG, Das wird Oben bereits überprüft mit isConnection found, dann wird zurück gegeben das es der gleiche Spieler noch ist
            
            // Prüfe ob Duplikat in aktueller History
            let isDuplicate = history.contains{ oldDart in
                hypot(oldDart.x - newDart.x, oldDart.y - newDart.y) < tolerance
            }
            
            if isDuplicate {
                print("⚠️ Duplikat erkannt, überspringe Dart")
                continue  // Überspringe diesen Dart, aber verarbeite weitere
            }
            
            // Neuen Dart hinzufügen
            history.append(newDart)
            
            
            let currentScores = history.map { $0.score }
            onScoresUpdated?(currentScores)
        }
        
        if historyOld.count == history.count {
            return.sameRound
        }
        
        if previousCount == history.count && !history.isEmpty{
            return .sameRound
        }
        
        // Wir geben das Signal "update" mit der neuen Liste zurück
        return .update(history)
    }
    
    func reset() {
        // Alte Pfeile merken, bevor wir resetten (für nächsten Spieler)
        ignoredDarts = history
        print("💾 Merke \(history.count) alte Pfeile zum Ignorieren")
        
        // History für neuen Spieler leeren
        history.removeAll()
        onScoresUpdated?([])
    }
    
    func clearIgnored() {
        // Ignore-Liste leeren (wenn Pfeile gezogen wurden)
        ignoredDarts.removeAll()
        print("🗑️ Ignore-Liste geleert")
    }
    func getHistoryCount() -> Int {
        return history.count
    }
}
