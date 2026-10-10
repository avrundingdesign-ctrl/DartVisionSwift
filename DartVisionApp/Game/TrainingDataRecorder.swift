import Foundation
import CoreGraphics

/// Speichert Bilder, bei denen die KI korrigiert werden musste – genau diese Fälle bringen beim
/// Nachtrainieren am meisten. Ablage: Dateien-App → Auf meinem iPhone → DartVision → TrainingData.
nonisolated enum TrainingDataRecorder {

    nonisolated struct DartRecord: Codable, Sendable {
        var label: String
        var points: Int
        var source: String
        var confidence: Double?
        /// Position auf dem Board (mm, Ursprung Bull, y nach oben).
        var boardPoint: CGPoint?
        /// Position im gespeicherten Bild (Pixel, oben links).
        var imagePoint: CGPoint?
    }

    nonisolated struct Sample: Codable, Sendable {
        var createdAt: Date
        var imageFile: String
        var imageSize: CGSize
        /// Kalibrierpunkte im gespeicherten Bild: top (5/20), right (13/6), bottom (17/3), left (8/11).
        var keypoints: BoardKeypoints
        var detected: [DartRecord]
        var corrected: [DartRecord]
    }

    static var directory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("TrainingData", isDirectory: true)
    }

    static var sampleCount: Int {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }.count
    }

    static func save(jpeg: Data, sample: Sample) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try jpeg.write(to: directory.appendingPathComponent(sample.imageFile), options: .atomic)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let json = try encoder.encode(sample)
            let name = (sample.imageFile as NSString).deletingPathExtension + ".json"
            try json.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            // Trainingsdaten sind optional – Fehler dürfen das Spiel nicht stören.
        }
    }
}
