import SwiftUI

@main
struct FinanceApp: App {
    @State private var portfolio: Portfolio
    @State private var palette: Palette

    init() {
        let portfolio = Portfolio.load()
        if UserDefaults.standard.bool(forKey: ProPreview.freshKey) {
            portfolio.beginFirstUse()
        }
        _portfolio = State(initialValue: portfolio)
        _palette = State(initialValue: Palette.load())
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(portfolio)
                .environment(palette)
                .preferredColorScheme(palette.colorScheme)
        }
    }
}
