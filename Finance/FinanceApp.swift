import StoreKit
import SwiftUI
import UIKit

@main
struct FinanceApp: App {
    @UIApplicationDelegateAdaptor(FinanceAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var portfolio: Portfolio
    @State private var palette: Palette
    @State private var proStore = ProStore()

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
                .environment(proStore)
                .preferredColorScheme(palette.colorScheme)
                .task { await proStore.listen() }
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

/// Portrait, unless the Duo is held hinge-up. Unfolding that pose stays landscape.
enum InterfaceLock {
    static var mask: UIInterfaceOrientationMask = .portrait

    static func apply(_ mask: UIInterfaceOrientationMask) {
        guard self.mask != mask else { return }
        self.mask = mask
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }
}

final class FinanceAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        InterfaceLock.mask
    }
}

/// One-time unlock. The gear menu can still preview a tier without a purchase.
@Observable
final class ProStore {
    static let productID = "com.deanaa776622.finance.pro"
    private(set) var product: Product?
    private(set) var note = ""
    private(set) var buying = false

    func listen() async {
        await refreshEntitlement()
        for await update in Transaction.updates {
            guard let transaction = try? update.payloadValue else { continue }
            await transaction.finish()
            grant(transaction)
        }
    }

    func load() async {
        product = try? await Product.products(for: [Self.productID]).first
        if product == nil { note = "讀不到價格" }
    }

    func buy() async -> Bool {
        if product == nil { await load() }
        guard let product else { return false }
        buying = true
        defer { buying = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard let transaction = try? verification.payloadValue else { return false }
                await transaction.finish()
                grant(transaction)
                note = ""
                return true
            case .pending:
                note = "等待確認"
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            note = "這次沒有完成"
            return false
        }
    }

    func restore() async -> Bool {
        buying = true
        defer { buying = false }
        do { try await AppStore.sync() } catch {
            note = "沒有找到已購買的紀錄"
            return false
        }
        let unlocked = await hasEntitlement()
        if unlocked {
            UserDefaults.standard.set(true, forKey: ProPreview.key)
            note = ""
        } else {
            note = "沒有找到已購買的紀錄"
        }
        return unlocked
    }

    private func refreshEntitlement() async {
        guard await hasEntitlement() else { return }
        UserDefaults.standard.set(true, forKey: ProPreview.key)
    }

    private func hasEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? result.payloadValue else { continue }
            if transaction.productID == Self.productID, transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    private func grant(_ transaction: StoreKit.Transaction) {
        guard transaction.productID == Self.productID, transaction.revocationDate == nil else { return }
        UserDefaults.standard.set(true, forKey: ProPreview.key)
    }
}
