import SwiftUI

struct CurrentThrowRow: View {
    // Wir bekommen die aktuellen Scores direkt aus dem Model
    var scores: [Int]

    var body: some View {
        HStack(spacing: 12) {
            // Wir erstellen immer genau 3 Kästchen
            ForEach(0..<3, id: \.self) { index in
                let scoreText = index < scores.count ? "\(scores[index])" : "-"
                let isFilled = index < scores.count
                
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isFilled ? Color.dvPrimary.opacity(0.15) : Color.gray.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isFilled ? Color.dvPrimary : Color.gray.opacity(0.3), lineWidth: 2)
                        )
                    
                    Text(scoreText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(isFilled ? .dvInk : .gray.opacity(0.5))
                }
                .frame(height: 60) // Höhe der Kästchen
                .frame(maxWidth: .infinity) // Volle Breite nutzen
            }
        }
    }
}
