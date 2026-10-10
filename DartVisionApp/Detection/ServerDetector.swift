import Foundation
import CoreGraphics

/// KI auf dem DartVision-Server (`/upload`, siehe CptFrechdachsRpt/V4_Server.py).
///
/// Unterschiede zur alten Implementierung:
/// - Bild wird aufrecht und auf max. 2048 px verkleinert gesendet (statt 12 MP mit Qualität 1.0),
/// - Keypoints werden zwischen Upload- und Kameraauflösung umgerechnet,
/// - die Wertung wird lokal aus den Board-Koordinaten berechnet (inkl. Draht-Abstand).
actor ServerDetector: DartDetector {

    nonisolated let displayName = "Server"
    nonisolated let preferredInterval: TimeInterval = 0.15
    nonisolated let cheapBoardCheck = false
    nonisolated let endpoint: URL

    private let renderer = FrameRenderer()
    private let session: URLSession
    private var tuning = DetectorTuning()
    private let maxUploadDimension: CGFloat = 2048

    init(endpoint: URL) {
        self.endpoint = endpoint
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func updateTuning(_ tuning: DetectorTuning) async {
        self.tuning = tuning
    }

    func detectBoard(in frame: AnalysisFrame) async throws -> BoardDetection {
        let upload = try renderer.jpeg(from: frame.pixelBuffer, maxDimension: maxUploadDimension, quality: 0.85)
        let json = try await post(jpeg: upload.data, keypoints: nil)
        let scaleX = frame.size.width / upload.size.width
        let scaleY = frame.size.height / upload.size.height
        return Self.parseBoard(json, scaleX: scaleX, scaleY: scaleY)
    }

    func detectDarts(in frame: AnalysisFrame, calibration: BoardCalibration) async throws -> [DartCandidate] {
        let upload = try renderer.jpeg(from: frame.pixelBuffer, maxDimension: maxUploadDimension, quality: 0.85)
        let keypoints = calibration.keypoints.scaled(x: upload.size.width / frame.size.width,
                                                     y: upload.size.height / frame.size.height)
        let json = try await post(jpeg: upload.data, keypoints: keypoints)
        return Self.parseDarts(json, minConfidence: tuning.minConfidence)
    }

    // MARK: - HTTP

    private func post(jpeg: Data, keypoints: BoardKeypoints?) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        let boundary = "DartVision-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var keypointJSON = "{}"
        if let keypoints {
            let payload: [String: [Double]] = [
                "top": [Double(keypoints.top.x), Double(keypoints.top.y)],
                "right": [Double(keypoints.right.x), Double(keypoints.right.y)],
                "bottom": [Double(keypoints.bottom.x), Double(keypoints.bottom.y)],
                "left": [Double(keypoints.left.x), Double(keypoints.left.y)]
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            keypointJSON = String(decoding: data, as: UTF8.self)
        }

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"keypoints\"\r\n\r\n".utf8))
        body.append(Data(keypointJSON.utf8))
        body.append(Data("\r\n--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"dart.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            throw DetectionError.network(error.localizedDescription)
        }
        let (data, response) = result

        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = object?["error"] as? String ?? "HTTP \(http.statusCode)"
            throw DetectionError.server(message)
        }
        guard let json = object else { throw DetectionError.server("Ungültige Antwort") }
        if let message = json["error"] as? String { throw DetectionError.server(message) }
        return json
    }

    // MARK: - Antwort auswerten

    nonisolated static func parseBoard(_ json: [String: Any], scaleX: CGFloat, scaleY: CGFloat) -> BoardDetection {
        let keypoints = json["keypoints"] as? [String: Any] ?? [:]
        let confidences = json["keypoint_confidences"] as? [String: Any] ?? [:]
        var points: [CGPoint?] = []
        var scores: [Double] = []
        for name in ["top", "right", "bottom", "left"] {
            if let pair = keypoints[name] as? [Any], pair.count >= 2,
               let x = number(pair[0]), let y = number(pair[1]) {
                points.append(CGPoint(x: CGFloat(x) * scaleX, y: CGFloat(y) * scaleY))
                scores.append(number(confidences[name]) ?? 1)
            } else {
                points.append(nil)
                scores.append(0)
            }
        }
        let found = points.compactMap { $0 }
        return BoardDetection(keypoints: found.count == 4 ? BoardKeypoints(points: found) : nil,
                              confidences: scores, partialPoints: points)
    }

    /// Der Server liefert Dart-Koordinaten im entzerrten 400×400-Board (Radius 200 = Doppelring außen).
    nonisolated static func parseDarts(_ json: [String: Any], minConfidence: Double) -> [DartCandidate] {
        guard let darts = json["darts"] as? [[String: Any]] else { return [] }
        let mmPerUnit = BoardGeometry.doubleOuterRadius / 200.0
        return darts.compactMap { dart in
            guard let x = number(dart["x"]), let y = number(dart["y"]) else { return nil }
            let confidence = number(dart["confidence"]) ?? 0.8
            guard confidence >= minConfidence else { return nil }
            let boardPoint = CGPoint(x: (x - 200) * mmPerUnit, y: (200 - y) * mmPerUnit)
            return DartCandidate(boardPoint: boardPoint, confidence: confidence, imagePoint: nil)
        }
    }

    nonisolated private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
