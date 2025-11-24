import CoreGraphics

struct TrackedDart: Equatable {
    var position: CGPoint
    var score: Int
}

final class DartTracker {
    private var tracked: [TrackedDart] = []
    private let tolerance: CGFloat

    init(tolerance: CGFloat) {
        self.tolerance = tolerance
    }

    func reset() {
        tracked.removeAll()
    }

    func merge(with detections: [DartData]) -> [TrackedDart] {
        guard !detections.isEmpty else { return tracked }

        var usedIndices = Set<Int>()
        var updated: [TrackedDart] = []
        var unmatchedOld: [TrackedDart] = []

        for old in tracked {
            if let matchIndex = nearestMatch(for: old, in: detections, excluding: usedIndices) {
                usedIndices.insert(matchIndex)
                let match = detections[matchIndex]
                updated.append(TrackedDart(position: CGPoint(x: match.x, y: match.y),
                                           score: match.score))
            } else {
                unmatchedOld.append(old)
            }
        }

        let remainingIndices = detections.indices
            .filter { !usedIndices.contains($0) }
            .sorted { lhs, rhs in
                let left = detections[lhs]
                let right = detections[rhs]
                return (left.x + left.y) < (right.x + right.y)
            }

        for index in remainingIndices {
            let data = detections[index]
            if updated.count < 3 {
                updated.append(TrackedDart(position: CGPoint(x: data.x, y: data.y),
                                           score: data.score))
            }
        }

        if updated.count < 3 {
            for old in unmatchedOld {
                if updated.count >= 3 { break }
                updated.append(old)
            }
        }

        tracked = updated
        return tracked
    }

    private func nearestMatch(for dart: TrackedDart,
                              in detections: [DartData],
                              excluding used: Set<Int>) -> Int? {
        var bestIndex: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for (index, detection) in detections.enumerated() where !used.contains(index) {
            let dx = dart.position.x - detection.x
            let dy = dart.position.y - detection.y
            let distance = sqrt(dx * dx + dy * dy)

            guard distance <= tolerance else { continue }

            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestIndex
    }
}
