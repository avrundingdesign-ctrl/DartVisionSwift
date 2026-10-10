import SwiftUI
import Foundation

struct ResultsView: View {
    @Environment(AppModel.self) private var app
    let session: GameSession

    var body: some View {
        let snapshot = session.snapshot
        let winner = snapshot.matchWinner ?? snapshot.legWinner

        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(colors: [Color.dvGold, Color(hex: 0xFF7A3D)], startPoint: .top, endPoint: .bottom)
                        )
                        .symbolEffect(.bounce, value: winner)
                        .padding(.top, 24)
                    if let winner {
                        Text(session.players[winner])
                            .font(.dvWordmark(52))
                            .foregroundStyle(Color.dvText)
                            .multilineTextAlignment(.center)
                        Text("gewinnt das Spiel")
                            .font(.dvRounded(16, weight: .semibold))
                            .foregroundStyle(Color.dvTextSecondary)
                    } else {
                        Text("Spiel beendet")
                            .font(.dvWordmark(44))
                            .foregroundStyle(Color.dvText)
                    }
                    if session.match.settings.bestOfLegs > 1 {
                        Text(snapshot.legsWon.map(String.init).joined(separator: " : "))
                            .font(.dvNumber(34, weight: .heavy))
                            .foregroundStyle(Color.dvGold)
                    }
                }

                VStack(spacing: 12) {
                    ForEach(session.players.indices, id: \.self) { index in
                        statsCard(index: index, stats: snapshot.stats[index], isWinner: index == winner)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button {
                    app.endSession()
                } label: {
                    Label("Zum Start", systemImage: "house.fill")
                }
                .buttonStyle(DVButtonStyle(kind: .secondary, height: 56))
                Button {
                    app.rematch()
                } label: {
                    Label("Revanche", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(DVButtonStyle(kind: .primary, height: 56))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.dvBackground)
        }
        .background(Color.dvBackground.ignoresSafeArea())
    }

    private func statsCard(index: Int, stats: PlayerStats, isWinner: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(session.players[index])
                    .font(.dvRounded(18, weight: .bold))
                    .foregroundStyle(Color.dvText)
                if isWinner {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(Color.dvGold)
                }
                Spacer()
                Text(String(format: "Ø %.1f", stats.threeDartAverage))
                    .font(.dvNumber(22, weight: .heavy))
                    .foregroundStyle(Color.dvText)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    stat("Darts", "\(stats.darts)")
                    stat("Höchste Aufnahme", "\(stats.bestTurn)")
                }
                GridRow {
                    stat("Höchstes Finish", stats.highestCheckout > 0 ? "\(stats.highestCheckout)" : "–")
                    stat("180er", "\(stats.count180)")
                }
                GridRow {
                    stat("140+", "\(stats.count140Plus)")
                    stat("100+", "\(stats.count100Plus)")
                }
            }
        }
        .dvCard(highlighted: isWinner)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.dvRounded(12, weight: .medium))
                .foregroundStyle(Color.dvTextTertiary)
            Text(value)
                .font(.dvNumber(18, weight: .bold))
                .foregroundStyle(Color.dvText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
