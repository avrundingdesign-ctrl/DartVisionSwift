import Foundation
import CoreMotion
import Observation

/// Erkennt, ob das iPhone ruhig steht und ob es seit der Kalibrierung bewegt wurde.
@Observable
final class MotionMonitor {

    /// Gerät ist seit mindestens einer Sekunde ruhig.
    private(set) var isStill = true
    /// Zählt deutliche Bewegungen – Beobachter prüfen danach die Kalibrierung.
    private(set) var movementCount = 0

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var stillSince: Date?
    @ObservationIgnored private var inMovement = false

    /// Schwellwerte (Rotation in rad/s + Beschleunigung in g, gewichtet).
    @ObservationIgnored private let movingThreshold = 0.35
    @ObservationIgnored private let stillThreshold = 0.08
    @ObservationIgnored private let stillDuration: TimeInterval = 1.0

    func start() {
        guard pollTask == nil, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 0.1
        manager.startDeviceMotionUpdates()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        manager.stopDeviceMotionUpdates()
        isStill = true
        inMovement = false
        stillSince = nil
    }

    private func poll() {
        guard let motion = manager.deviceMotion else { return }
        let rotation = abs(motion.rotationRate.x) + abs(motion.rotationRate.y) + abs(motion.rotationRate.z)
        let acceleration = abs(motion.userAcceleration.x) + abs(motion.userAcceleration.y) + abs(motion.userAcceleration.z)
        let energy = rotation + acceleration * 3

        if energy > movingThreshold {
            stillSince = nil
            if isStill { isStill = false }
            if !inMovement {
                inMovement = true
                movementCount += 1
            }
        } else if energy < stillThreshold {
            let now = Date()
            if stillSince == nil { stillSince = now }
            if let since = stillSince, !isStill, now.timeIntervalSince(since) >= stillDuration {
                isStill = true
                inMovement = false
            }
        }
    }
}
