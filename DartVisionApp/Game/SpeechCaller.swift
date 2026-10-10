import Foundation
import AVFoundation
import Observation

/// Sprachausgabe im Stil eines Darts-Callers.
@Observable
final class SpeechCaller {

    var isEnabled = true

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var voice: AVSpeechSynthesisVoice?
    @ObservationIgnored private var audioPrepared = false

    init() {
        voice = Self.bestGermanVoice()
    }

    /// Wiedergabe auch im Stumm-Modus, andere Audioquellen werden nur kurz leiser.
    func prepareAudioSession() {
        guard !audioPrepared else { return }
        let audio = AVAudioSession.sharedInstance()
        do {
            try audio.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audio.setActive(true)
            audioPrepared = true
        } catch {
            audioPrepared = false
        }
    }

    func say(_ text: String, interrupt: Bool = false) {
        guard isEnabled, !text.isEmpty else { return }
        prepareAudioSession()
        if interrupt && synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Beste installierte deutsche Stimme (Premium > Erweitert > Standard).
    private static func bestGermanVoice() -> AVSpeechSynthesisVoice? {
        let german = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "de-DE" }
        return german.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "de-DE")
    }
}
