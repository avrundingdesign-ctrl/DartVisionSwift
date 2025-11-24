import Foundation
import CoreGraphics

struct ServerResponse: Codable {
    var keypoints: ServerKeypoints
    var darts: [DartData]
}

struct ServerKeypoints: Codable {
    var top: [CGFloat]
    var right: [CGFloat]
    var bottom: [CGFloat]
    var left: [CGFloat]
}

struct DartData: Codable, Identifiable {
    var id = UUID()
    var x: CGFloat
    var y: CGFloat
    var score: Int
    
    private enum CodingKeys: String, CodingKey {
        case x, y, score
    }
}
