import Foundation

// MARK: - Globale Notification Names für App-Kommunikation
extension Notification.Name {
    /// Wird gesendet, wenn ein Wurf (3 Darts) abgeschlossen wurde.
    static let didFinishTurn = Notification.Name("didFinishTurn")
    static let Throw = Notification.Name("Throw")

    /// Optional: Kannst du später nutzen, wenn du auch Start/Reset signalisieren willst.
    static let didStartGame = Notification.Name("didStartGame")
    static let didResetGame = Notification.Name("didResetGame")
    static let deviceWasStillFor2Sec = Notification.Name("deviceWasStillFor2Sec")
}
