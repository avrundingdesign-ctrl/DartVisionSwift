import Combine
import SwiftUI
import AVFoundation
import Foundation

@MainActor
final class CameraModel: NSObject,
                         ObservableObject,
                         AVCapturePhotoCaptureDelegate,
                         AVSpeechSynthesizerDelegate {

    // MARK: - Kamera & Bewegung
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var captureTimer: Timer?
    private var timer: Timer?
    var photoHandler: ((UIImage) -> Void)?
    let motionDetector = MotionDetector()
    let dartTracker = DartTracker()

    // MARK: - Flags & State
    private var cancellables = Set<AnyCancellable>()
    private var didInstallStillObserver = false
    private var isCapturingNow = false
    @Published var isGameActive = true
    @Published var isThrowBusted = false
    @Published private(set) var isSpeaking = false

    // MARK: - Sprache
    let synthesizer = AVSpeechSynthesizer()

    // MARK: - Init
    override init() {
        super.init()
        synthesizer.delegate = self      // Delegate sofort aktiv – isSpeaking ist ab der ersten Ansage korrekt
    }

    // MARK: - Game Data
    @Published var currentGame = GameData()
    private var lastDartPositions: [(x: CGFloat, y: CGFloat)] = []
    

    // MARK: - Observer (nur einmal)
    private func observeDeviceStillnessOnce() {
        guard !didInstallStillObserver else { return }
        didInstallStillObserver = true

        NotificationCenter.default.addObserver(
            forName: .deviceWasStillFor2Sec,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isGameActive, !self.isCapturingNow else { return }
                print("📱 Gerät 2 Sekunden still → Keypoints zurückgesetzt.")
                self.currentGame.keypoints = nil
            }
        }
    }

    // MARK: - Kamera konfigurieren
    func configure() {
        session.beginConfiguration()

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            print("❌ Kamera konnte nicht initialisiert werden.")
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }

        session.commitConfiguration()
        session.startRunning()
        print("📸 Kamera konfiguriert.")
    }

    // MARK: - AVSpeechSynthesizerDelegate
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
        print("🗣️ Start Speech: \(utterance.speechString)")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        print("✅ End Speech: \(utterance.speechString)")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        print("⏹️ Cancel Speech: \(utterance.speechString)")
    }

    // MARK: - Aufnahme starten (mit Stillness-Gate)
    func startCapturing(photoHandler: @escaping (UIImage) -> Void) {
        self.photoHandler = photoHandler

        observeDeviceStillnessOnce()
        motionDetector.startMonitoring()

        if !session.isRunning {
            session.startRunning()
        }

        captureTimer?.invalidate()
        captureTimer = nil
        isCapturingNow = false

        // 🔁 Alle 4 s prüfen, ob Gerät ruhig ist → Foto schießen
        captureTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isGameActive else { return }
                guard self.motionDetector.hasBeenStillFor2Sec else { 
                    print("⏸️ Gerät nicht still genug")
                    return 
                }
                guard !self.isCapturingNow else { return }
                guard !self.isSpeaking else { return }           // nie während TTS fotografieren

                print("📸 Mache Foto...")
                self.isCapturingNow = true
                let settings = AVCapturePhotoSettings()
                self.output.capturePhoto(with: settings, delegate: self)
            }
        }

        print("▶️ Auto-Capture gestartet.")
    }

    // MARK: - Aufnahme stoppen
    func stopCapturing() {
        captureTimer?.invalidate()
        captureTimer = nil
        timer?.invalidate()
        timer = nil
        isCapturingNow = false
        motionDetector.stopMonitoring()
        print("🛑 Aufnahme gestoppt.")
    }

    // MARK: - Lautloses Foto (optional)
    private func captureSilentPhoto() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, options: [.mixWithOthers])
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        defer { self.isCapturingNow = false }

        if let error = error {
            print("❌ Fotoverarbeitung fehlgeschlagen:", error.localizedDescription)
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            print("⚠️ Konnte Bilddaten nicht lesen.")
            return
        }

        // In Fotos-App speichern (Album: DartImages)
        PhotosSaver.save(image, toAlbum: "DartImages") { result in
            switch result {
            case .success:
                print("✅ Foto in Fotos-App gespeichert (Album: DartImages).")
            case .failure(let error):
                print("❌ Speichern fehlgeschlagen:", error.localizedDescription)
            }
        }

        print("📸 Foto aufgenommen, rufe photoHandler auf...")
        // Optional: Callback weiterreichen
        photoHandler?(image)
        print("✅ photoHandler wurde aufgerufen")
    }


    // MARK: - Upload zum Server
    func uploadImageToServer(_ image: UIImage) {
        print("📤 uploadImageToServer aufgerufen")
        
        guard let url = URL(string: "http://192.168.178.106:5000/upload"),
              let jpegData = image.jpegData(compressionQuality: 1.0) else {
            print("❌ URL oder JPEG-Konvertierung fehlgeschlagen")
            return
        }
        
        print("📤 Sende \(jpegData.count / 1024) KB an \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Keypoints mitsenden (falls vorhanden)
        if let kp = currentGame.keypoints {
            print("📍 Verwende gespeicherte Keypoints für Upload:", kp)
            let kpDict: [String: [CGFloat]] = [
                "top": [kp.top.x, kp.top.y],
                "right": [kp.right.x, kp.right.y],
                "bottom": [kp.bottom.x, kp.bottom.y],
                "left": [kp.left.x, kp.left.y]
            ]
            if let kpData = try? JSONSerialization.data(withJSONObject: kpDict, options: [.prettyPrinted]) {
                let kpString = String(data: kpData, encoding: .utf8) ?? "{}"
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"keypoints\"\r\n\r\n".data(using: .utf8)!)
                body.append(kpString.data(using: .utf8)!)
                body.append("\r\n".data(using: .utf8)!)
            }
        } else {
            print("⚠️ Keine Keypoints gespeichert – sende leeres Feld.")
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"keypoints\"\r\n\r\n{}\r\n".data(using: .utf8)!)
        }

        // Bilddaten
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"dart.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpegData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        print("📤 Starte Upload-Request...")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                print("📥 Server antwortet mit Status: \(httpResponse.statusCode)")
            }
            
            if let error {
                print("❌ Upload-Fehler:", error.localizedDescription)
                return
            }

            guard let data else {
                print("⚠️ Keine Daten vom Server erhalten.")
                return
            }

            // Für Swift 6: auf MainActor decodieren (oder ServerResponse entkoppeln/Sendable machen)
            Task { @MainActor in
                do {
                    let decoded = try JSONDecoder().decode(ServerResponse.self, from: data)
                    self.updateFromServer(decoded)
                } catch {
                    print("⚠️ JSON-Decode-Fehler:", error)
                }
            }

        }.resume()
    }

    // MARK: - Daten übernehmen
    private func updateFromServer(_ decoded: ServerResponse) {
        let k = decoded.keypoints
        let allKeypoints = [k.top, k.right, k.bottom, k.left]
        let hasAllKeypoints = allKeypoints.allSatisfy { $0.count == 2 }

        if !hasAllKeypoints {
            print("⚠️ Ungültige oder unvollständige Keypoints → reset & restart.")
            currentGame.keypoints = nil

            // TTS-sicherer Neustart
            scheduleSafeRestart(after: 3.0)
            return
        }

        // Keypoints speichern (einmalig)
        if currentGame.keypoints == nil {
            print("💾 Speichere initiale Keypoints vom Server.")
            currentGame.keypoints = Keypoints(
                top: CGPoint(x: k.top[0], y: k.top[1]),
                right: CGPoint(x: k.right[0], y: k.right[1]),
                bottom: CGPoint(x: k.bottom[0], y: k.bottom[1]),
                left: CGPoint(x: k.left[0], y: k.left[1])
            )
        } else {
            print("🧊 Board-Keypoints fixiert – neue Keypoints ignoriert.")
        }

        // Darts verarbeiten
        
  
            // Funktionsaufruf
            let countBefore = dartTracker.getHistoryCount()
            let result = dartTracker.merge(with: decoded.darts, isBusted: self.isThrowBusted)

            switch result {
                
                case .sameRound:
                // Wenn Liste = 3 && Dann gleicher Dart in der nächsten Runde,
                    print("Alte Runde erkannt (3 Darts stecken noch).")
                

                case .update(let currentDarts):
                    if currentDarts.count > countBefore {
                        for i in countBefore..<currentDarts.count {
                            let newDart = currentDarts[i]
                            let dartNumber = i + 1 // Der wievielte Dart ist das in der Runde?

                            if dartNumber < 3 {
                                // Dart 1 oder 2
                                DispatchQueue.main.async {
                                    NotificationCenter.default.post(name: .Throw, object: newDart)
                                }
                            } else {
                                // Dart 3 -> Turn beendet
                                
                                let totalScore = currentDarts.reduce(0) { $0 + $1.score }
                                
                                
                                // Sprachausgabe
                                prepareAudioForSpeech()
                                let utterance = AVSpeechUtterance(string: "\(totalScore)")
                                utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
                                synthesizer.speak(utterance)

                                DispatchQueue.main.async {
                                    NotificationCenter.default.post(name: .didFinishTurn, object: newDart)
                                }
                            }
                        }
                    }
                
            }

            // Nach Verarbeitung neu starten – aber nie während TTS
            scheduleSafeRestart(after: 1.0)

    }

    // MARK: - TTS-sicherer Restart-Helfer
    private func scheduleSafeRestart(after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            guard self.isGameActive, let handler = self.photoHandler else { return }
            if self.isSpeaking {
                print("⏳ Sprach-Ausgabe läuft noch – verschiebe neuen Capture.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    guard self.isGameActive, !self.isSpeaking, let handler = self.photoHandler else { return }
                    self.stopCapturing()
                    self.startCapturing(photoHandler: handler)
                }
            } else {
                self.stopCapturing()
                self.startCapturing(photoHandler: handler)
            }
        }
    }

    // MARK: - Audio-Routing für Sprachausgabe
    private func prepareAudioForSpeech() {
        let audioSession = AVAudioSession.sharedInstance()
        // Playback-Kategorie erzwingt Lautsprecher-Ausgabe.
        // duckOthers = andere Audios kurz leiser, defaultToSpeaker = Lautsprecher statt Ohrmuschel.
        try? audioSession.setCategory(.playback, options: [.duckOthers, .defaultToSpeaker])
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Utils
    func areKeypointsEqual(_ a: Keypoints?, _ b: Keypoints?, tolerance: CGFloat = 1.0) -> Bool {
        guard let a, let b else { return false }
        func close(_ p1: CGPoint, _ p2: CGPoint) -> Bool {
            abs(p1.x - p2.x) <= tolerance && abs(p1.y - p2.y) <= tolerance
        }
        return close(a.top, b.top) &&
               close(a.right, b.right) &&
               close(a.bottom, b.bottom) &&
               close(a.left, b.left)
    }

    // MARK: - Cleanup
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

