import SwiftUI

@main
struct FinanceApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var portfolio: Portfolio
    @State private var palette: Palette

    init() {
        let portfolio = Portfolio.load()
        if UserDefaults.standard.bool(forKey: ProPreview.freshKey) {
            portfolio.beginFirstUse()
        }
        _portfolio = State(initialValue: portfolio)
        _palette = State(initialValue: Palette.load())
        ICloudBackup.register()
        ICloudBackup.refreshSchedule()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(portfolio)
                .environment(palette)
                .preferredColorScheme(palette.colorScheme)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { ICloudBackup.backupIfDue() }
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    ICloudBackup.backupIfDue()
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(30))
                        ICloudBackup.backupIfDue()
                    }
                }
        }
    }
}
