import SwiftUI
import Foundation

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = app.settings
        NavigationStack {
            Form {
                Section {
                    Picker("Erkennung", selection: $settings.backend) {
                        ForEach(DetectionBackend.allCases) { backend in
                            Text(backend.title).tag(backend)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!OnDeviceDetector.modelsAvailable)

                    if settings.backend == .server {
                        TextField("Server-Adresse", text: $settings.serverURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if !OnDeviceDetector.modelsAvailable {
                        Label("Keine KI-Modelle im App-Bundle – nur Server möglich.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.dvGold)
                    }
                } header: {
                    Text("Erkennung")
                } footer: {
                    Text("Auf dem iPhone ist die Erkennung schneller (ca. 3 Bilder/s), funktioniert offline und kein Bild verlässt das Gerät.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Mindest-Konfidenz")
                            Spacer()
                            Text("\(Int((settings.minConfidence * 100).rounded())) %")
                                .monospacedDigit()
                                .foregroundStyle(Color.dvTextSecondary)
                        }
                        Slider(value: $settings.minConfidence, in: 0.2...0.7, step: 0.05)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Board-Zoom (experimentell)")
                            Spacer()
                            Text(String(format: "%.1f×", settings.maxBoardZoom))
                                .monospacedDigit()
                                .foregroundStyle(Color.dvTextSecondary)
                        }
                        Slider(value: $settings.maxBoardZoom, in: 1.0...2.0, step: 0.1)
                    }
                } header: {
                    Text("Genauigkeit")
                } footer: {
                    Text("Höhere Konfidenz bedeutet weniger Fehlerkennungen, aber eventuell übersehene Darts. Der Board-Zoom analysiert nur den Bereich ums Board und erhöht so die Auflösung für die Dartspitzen – vorher unter „Diagnose“ mit den Testbildern prüfen.")
                }

                Section {
                    Toggle("Sprachausgabe", isOn: $settings.speechEnabled)
                    Toggle("Jeden Dart ansagen", isOn: $settings.announceEveryDart)
                        .disabled(!settings.speechEnabled)
                } header: {
                    Text("Caller")
                }

                Section {
                    Toggle("Trainingsdaten sammeln", isOn: $settings.collectTrainingData)
                    LabeledContent("Gespeicherte Beispiele", value: "\(TrainingDataRecorder.sampleCount)")
                } header: {
                    Text("KI verbessern")
                } footer: {
                    Text("Speichert bei jeder Korrektur das Kamerabild mit den richtigen Werten (Dateien-App → Auf meinem iPhone → DartVision → TrainingData). Genau diese Fehlerfälle verbessern das Modell beim Nachtrainieren am stärksten.")
                }

                Section {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label("Diagnose & Selbsttest", systemImage: "stethoscope")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.dvBackground)
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationBackground(Color.dvBackground)
    }
}
