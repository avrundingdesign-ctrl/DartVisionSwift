/*import SwiftUI

struct ScoreCorrectionView: View {
    @State private var selectedDart: Int? = nil
    @State private var dartValues: [Int] = [0, 0, 0]
    @State private var dartMultipliers: [Int] = [1, 1, 1]

    var onConfirm: (Int) -> Void
    var onCancel: () -> Void

    private func totalScore() -> Int {
        zip(dartValues, dartMultipliers).map(*).reduce(0, +)
    }

    var body: some View {
        ZStack {
            // Hintergrund abdunkeln
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { onCancel() }

            VStack(spacing: 18) {
                Text("Korrigiere deinen Wurf")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.dvInk)
                    .padding(.top, 10)

                // Darts (1–3)
                HStack(spacing: 16) {
                    ForEach(0..<3, id: \.self) { i in
                        VStack(spacing: 6) {
                            Text("Dart \(i+1)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)

                            Button {
                                selectedDart = i
                            } label: {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedDart == i ? Color.dvPrimary.opacity(0.15) : Color.dvMode.opacity(0.1))
                                    .frame(width: 80, height: 65)
                                    .overlay(
                                        Text(displayValue(for: i))
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundColor(.dvInk)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Kompaktes Eingabefeld (1–20, D/T)
                if let active = selectedDart {
                    numberPad(for: active)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.25), value: selectedDart)
                }

                // Footer-Buttons
                HStack(spacing: 20) {
                    Button(action: { onCancel() }) {
                        Text("Abbrechen")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.dvGray.opacity(0.3)))
                            .foregroundColor(.black)
                    }

                    Button(action: {
                        onConfirm(totalScore())
                    }) {
                        Text("Übernehmen")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.dvPrimary))
                            .foregroundColor(.white)
                    }
                    .disabled(dartValues.allSatisfy { $0 == 0 })
                }
                .padding(.top, 8)
            }
            .padding(25)
            .frame(maxWidth: 360)
            .frame(minHeight: selectedDart == nil ? 300 : 420) // 🔹 kompakt halten
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            )
            .padding()
        }
    }

    // MARK: - Anzeigehilfe

    private func displayValue(for i: Int) -> String {
        let v = dartValues[i]
        let m = dartMultipliers[i]
        guard v > 0 else { return "-" }
        switch m {
        case 2: return "D\(v)"
        case 3: return "T\(v)"
        default: return "\(v)"
        }
    }

    // MARK: - Eingabe-Grid (kompakt)

    @ViewBuilder
    private func numberPad(for index: Int) -> some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(1...20, id: \.self) { n in
                    Button {
                        dartValues[index] = n
                    } label: {
                        Text("\(n)")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(dartValues[index] == n ? Color.dvPrimary.opacity(0.15) : Color.dvMode.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(dartValues[index] == n ? Color.dvPrimary : Color.clear, lineWidth: 1.5)
                            )
                    }
                    .foregroundColor(.dvInk)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)

            // D / T Buttons unter der Zahlentafel
            HStack(spacing: 12) {
                toggleButton(label: "D", active: dartMultipliers[index] == 2) {
                    dartMultipliers[index] = dartMultipliers[index] == 2 ? 1 : 2
                }
                toggleButton(label: "T", active: dartMultipliers[index] == 3) {
                    dartMultipliers[index] = dartMultipliers[index] == 3 ? 1 : 3
                }
            }
            .padding(.top, 4)
        }
        .padding(.bottom, 4)
    }

    private func toggleButton(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .bold))
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Capsule().fill(active ? Color.dvPrimary.opacity(0.15) : Color.dvMode.opacity(0.05)))
                .overlay(
                    Capsule().stroke(active ? Color.dvPrimary : Color.clear, lineWidth: 1.5)
                )
                .foregroundColor(.dvInk)
        }
        .buttonStyle(.plain)
    }
}
*/
