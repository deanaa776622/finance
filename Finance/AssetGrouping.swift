import Foundation

/// How the net-worth list slices assets. Derived from `AssetKind`; nothing extra is stored on an item.
enum AssetGrouping: String, CaseIterable, Identifiable {
    case overview, assets, liquid, stocks, nature

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "總覽"
        case .assets: "資產"
        case .liquid: "流動資產"
        case .stocks: "股票"
        case .nature: "性質"
        }
    }

    var buckets: [AssetBucket] {
        switch self {
        case .overview:
            [
                AssetBucket(id: "asset", title: "資產", kinds: [.original, .leverage, .cash, .realEstate]),
                AssetBucket(id: "debt", title: "負債", kinds: [.debt]),
            ]
        case .assets:
            [
                AssetBucket(id: "liquid", title: "流動", kinds: [.original, .leverage, .cash]),
                AssetBucket(id: "real", title: "實體", kinds: [.realEstate]),
            ]
        case .liquid:
            [
                AssetBucket(id: "stock", title: "股票", kinds: [.original, .leverage]),
                AssetBucket(id: "cash", title: "現金", kinds: [.cash]),
            ]
        case .stocks:
            [
                AssetBucket(id: "original", title: "原型", kinds: [.original]),
                AssetBucket(id: "leverage", title: "槓桿", kinds: [.leverage]),
            ]
        case .nature:
            AssetKind.allCases.map {
                AssetBucket(id: $0.rawValue, title: $0.compactTitle, kinds: [$0])
            }
        }
    }

    func storageID(for bucket: AssetBucket) -> String { "\(rawValue).\(bucket.id)" }
}

struct AssetBucket: Identifiable {
    var id: String
    var title: String
    var kinds: [AssetKind]
}
