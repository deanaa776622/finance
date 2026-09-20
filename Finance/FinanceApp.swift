import SwiftUI

@main
struct FinanceApp: App {
    @State private var portfolio = Portfolio.load()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(portfolio)
        }
    }
}
