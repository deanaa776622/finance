import Foundation

/// Last asset lens and which groups were open. Missing keys: 總淨值, all collapsed.
enum AssetListMemory {
    private static let lensKey = "assetLens"

    static var showsExposure: Bool {
        get { UserDefaults.standard.bool(forKey: lensKey) }
        set { UserDefaults.standard.set(newValue, forKey: lensKey) }
    }

    struct Groups {
        var assetsOpen: Bool
        var kinds: Set<AssetKind>
    }

    static func groups(exposure: Bool) -> Groups {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: kindsKey(exposure)) ?? ""
        let kinds = Set(raw.split(separator: ",").compactMap { AssetKind(rawValue: String($0)) })
        return Groups(assetsOpen: defaults.bool(forKey: openKey(exposure)), kinds: kinds)
    }

    static func save(exposure: Bool, assetsOpen: Bool, kinds: Set<AssetKind>) {
        let defaults = UserDefaults.standard
        defaults.set(assetsOpen, forKey: openKey(exposure))
        defaults.set(kinds.map(\.rawValue).sorted().joined(separator: ","), forKey: kindsKey(exposure))
    }

    private static func openKey(_ exposure: Bool) -> String {
        exposure ? "assetExposureOpen" : "assetNetOpen"
    }

    private static func kindsKey(_ exposure: Bool) -> String {
        exposure ? "assetExposureKinds" : "assetNetKinds"
    }
}
