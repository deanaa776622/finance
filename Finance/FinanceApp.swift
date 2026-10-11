import SwiftUI

@main
struct FinanceApp: App {
    @State private var portfolio = Portfolio.load()
    @State private var palette = Palette.load()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(portfolio)
                .environment(palette)
                .preferredColorScheme(.dark)
        }
    }
}
