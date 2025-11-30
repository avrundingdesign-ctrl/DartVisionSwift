import SwiftUI

struct WinOverlayView: View {
    let winnerName: String
    let resetAction: () -> Void
    
    var body: some View {
        ZStack {
            // Hintergrund abdunkeln und antippen verhindern
            Color.black.opacity(0.6).ignoresSafeArea()
            
            VStack(spacing: 25) {
                // 🏆 Pokal Icon (Schicker Look)
                Image(systemName: "trophy.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(Color(hex: "#FFD700")) // Gold
                    .shadow(color: .yellow, radius: 10, x: 0, y: 0)

                Text("SIEG!")
                    .font(.custom("Italiana-Regular", size: 50))
                    .foregroundColor(.dvInk)
                    .padding(.top, 5)

                Text("\(winnerName) hat gewonnen!")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.dvInk)
                    .multilineTextAlignment(.center)
                
                // Button zum Weitermachen
                Button(action: resetAction) {
                    Text("Neues Spiel starten")
                        .font(.system(size: 20, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.dvPrimary)
                        )
                        .foregroundColor(.white)
                }
            }
            .padding(40)
            .frame(maxWidth: 350)
            .background(
                RoundedRectangle(cornerRadius: 25)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            )
        }
    }
}
