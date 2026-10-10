import SwiftUI
import Foundation

@main
struct DartVisionApp: App {
    @State private var app = AppModel()

    init() {
        AppFonts.register()
        // Checkout-Tabellen im Hintergrund vorberechnen.
        Task.detached(priority: .utility) {
            _ = CheckoutCalculator.route(for: 170, outRule: .double)
            _ = CheckoutCalculator.route(for: 170, outRule: .master)
            _ = CheckoutCalculator.route(for: 170, outRule: .straight)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Color.dvBackground.ignoresSafeArea()
            switch app.route {
            case .home:
                HomeView()
                    .transition(.opacity)
            case .calibration:
                CalibrationView()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .game:
                if let session = app.session {
                    GameView(session: session)
                        .transition(.opacity)
                }
            case .results:
                if let session = app.session {
                    ResultsView(session: session)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: app.route)
        .preferredColorScheme(.dark)
        .tint(.dvRed)
    }
}
