import SwiftUI
import AVFoundation

struct GameModeSelectionView: View {
    @ObservedObject var cameraModel: CameraModel

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Spielmodus wählen")) {
                    ForEach(GameMode.allCases) { mode in
                        HStack {
                            Text(mode.rawValue)
                            Spacer()
                            if cameraModel.currentGame.mode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            cameraModel.currentGame.mode = mode
                            let utterance = AVSpeechUtterance(string: "\(mode.rawValue) Modus aktiviert")
                            utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
                            utterance.rate = 0.45
                            cameraModel.synthesizer.speak(utterance)
                        }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Modi")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
