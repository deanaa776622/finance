import Foundation

/// Last asset lens, and which exposure groups were open.
enum AssetListMemory {
    private static let lensKey = "assetLens"
    private static let exposureKindsKey = "assetExposureKinds"

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
}
