import SwiftUI

// MARK: - Add Player Button + Sheet (Variante 2)
struct AddPlayerButtonView: View {
    @Binding var players: [String]
    @State private var showAddPlayerSheet = false
    @State private var newPlayerName = ""

    var body: some View {
        Button {
            showAddPlayerSheet = true
        } label: {
            Text("Add Players")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.dvMode)
                )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showAddPlayerSheet) {
            VStack(spacing: 20) {
                Text("Add Players")
                    .font(.title2)
                    .bold()
                    .padding(.top)

                // 🧾 Liste der Spieler + Ei´ngabefeld
                List {
                    Section {
                        ForEach(players, id: \.self) { player in
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundColor(.dvPrimary)
                                Text(player)
                                    .font(.system(size: 17, weight: .regular))

                                Spacer()

                                // 🗑️ Delete Button
                                Button {
                                    if let index = players.firstIndex(of: player) {
                                        players.remove(at: index)
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                        }

                    }

                    Section {
                        HStack {
                            TextField("Enter name", text: $newPlayerName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .disableAutocorrection(true)
                                .autocapitalization(.words)

                            Button("Add") {
                                let trimmed = newPlayerName.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty && !players.contains(trimmed) && players.count < 2 {
                                    players.append(trimmed)
                                    newPlayerName = ""
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.dvPrimary)
                            .disabled(players.count >= 2)
                        }
                    }
                }
                .listStyle(.insetGrouped)

                Text("You can add up to 2 players.")
                    .font(.footnote)
                    .foregroundColor(.gray)

                Button("Done") {
                    showAddPlayerSheet = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.dvPrimary)
                .padding(.bottom, 10)
            }
            .presentationDetents([.fraction(0.55)])
        }
    }
}

// MARK: - Filter Button + Sheet (unverändert)
struct FilterButtonView: View {
    @Binding var selectedGame: Int?
    @Binding var doubleOut: Bool
    @State private var showFilterSheet = false

    var body: some View {
        Button {
            showFilterSheet = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.dvModeActive)
                )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showFilterSheet) {
            VStack(spacing: 25) {
                Text("Game Settings")
                    .font(.title2)
                    .bold()
                    .padding(.top)

                Picker("Mode", selection: $selectedGame) {
                    Text("301").tag(301 as Int?)
                    Text("501").tag(501 as Int?)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                Toggle("Double Out", isOn: $doubleOut)
                    .padding(.horizontal)
                    .toggleStyle(SwitchToggleStyle(tint: .dvPrimary))

                Spacer()
            }
            .presentationDetents([.fraction(0.4)])
        }
    }
}
