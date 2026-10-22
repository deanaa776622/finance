import Foundation
import Observation

/// Last asset lens, and which groups were open.
enum AssetListMemory {
    private static let lensKey = "assetLens"
    private static let exposureKindsKey = "assetExposureKinds"
    private static let netOpenGroupsKey = "assetNetOpenGroups"

    static var showsExposure: Bool {
        get { UserDefaults.standard.bool(forKey: lensKey) }
        set { UserDefaults.standard.set(newValue, forKey: lensKey) }
    }

    static var exposureKinds: Set<AssetKind> {
        get {
            let raw = UserDefaults.standard.string(forKey: exposureKindsKey) ?? ""
            return Set(raw.split(separator: ",").compactMap { AssetKind(rawValue: String($0)) })
        }
        set {
            let raw = newValue.map(\.rawValue).sorted().joined(separator: ",")
            UserDefaults.standard.set(raw, forKey: exposureKindsKey)
        }
    }

    static var netOpenGroups: Set<String> {
        get {
            let raw = UserDefaults.standard.string(forKey: netOpenGroupsKey) ?? ""
            return Set(raw.split(separator: ",").map(String.init))
        }
        set {
            UserDefaults.standard.set(newValue.sorted().joined(separator: ","), forKey: netOpenGroupsKey)
        }
    }
}

/// A group that was on screen just before a merge, restored when that merge splits.
struct AssetChild: Identifiable {
    var id: String
    var title: String
    var kinds: [AssetKind]
    var storageID: String
    var open: Bool
}

/// One lens's grouping. The home screen keeps a separate one for 總淨值 and 總曝險.
@Observable
final class AssetGroups {
    var stocksMerged = false
    var liquidMerged = false
    var assetMerged = false
    var netMerged = false
    var netHeldStocks = false
    var netHeldLiquid = false
    var netHeldAsset = false
    var assetHeldStocks = false
    var assetHeldLiquid = false
    var liquidHeldStocks = false
    var stockChildren: [AssetChild] = []
    var liquidChildren: [AssetChild] = []
    var assetChildren: [AssetChild] = []
    var netChildren: [AssetChild] = []
    var openGroupIDs: Set<String> = AssetListMemory.netOpenGroups
    var expandedKinds: Set<AssetKind> = AssetListMemory.exposureKinds
}
