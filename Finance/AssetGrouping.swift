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

/// Keeps the 原型 bucket's id so its header can retitle in place, and drops 槓桿.
func bucketsMergingStocks(_ buckets: [AssetBucket], merged: Bool) -> [AssetBucket] {
    guard merged,
          let original = buckets.firstIndex(where: { $0.kinds == [.original] }),
          let leverage = buckets.firstIndex(where: { $0.kinds == [.leverage] }),
          leverage == original + 1
    else { return buckets }
    var next = buckets
    let kept = next[original]
    next[original] = AssetBucket(id: kept.id, title: "股票", kinds: [.original, .leverage])
    next.remove(at: leverage)
    return next
}

/// Keeps the 原型 bucket's id and drops 槓桿 and 現金, so the header can retitle to 流動.
func bucketsMergingLiquid(_ buckets: [AssetBucket], merged: Bool) -> [AssetBucket] {
    guard merged,
          let original = buckets.firstIndex(where: { $0.kinds == [.original] }),
          let leverage = buckets.firstIndex(where: { $0.kinds == [.leverage] }),
          let cash = buckets.firstIndex(where: { $0.kinds == [.cash] }),
          leverage == original + 1,
          cash == leverage + 1
    else { return buckets }
    var next = buckets
    let kept = next[original]
    next[original] = AssetBucket(id: kept.id, title: "流動", kinds: [.original, .leverage, .cash])
    next.remove(at: cash)
    next.remove(at: leverage)
    return next
}

/// Folds 實體 and the asset groups directly above it into one 資產 bucket, keeping the top bucket's id.
func bucketsMergingAssets(_ buckets: [AssetBucket], merged: Bool) -> [AssetBucket] {
    guard merged, let range = assetJoinRange(buckets) else { return buckets }
    let order: [AssetKind] = [.original, .leverage, .cash, .realEstate]
    let kinds = order.filter { kind in buckets[range].contains { $0.kinds.contains(kind) } }
    var next = buckets
    let kept = next[range.lowerBound]
    next[range.lowerBound] = AssetBucket(id: kept.id, title: "資產", kinds: kinds)
    next.removeSubrange((range.lowerBound + 1)..<range.upperBound)
    return next
}

/// 實體 plus the contiguous original / leverage / cash buckets above it.
func assetJoinRange(_ buckets: [AssetBucket]) -> Range<Int>? {
    let cluster: Set<AssetKind> = [.original, .leverage, .cash]
    guard let real = buckets.firstIndex(where: { $0.kinds == [.realEstate] }), real > 0 else { return nil }
    var head = real
    while head > 0 {
        let kinds = buckets[head - 1].kinds
        guard !kinds.isEmpty, kinds.allSatisfy({ cluster.contains($0) }) else { break }
        head -= 1
    }
    guard head < real else { return nil }
    return head..<(real + 1)
}

struct AssetBucket: Identifiable {
    var id: String
    var title: String
    var kinds: [AssetKind]
}
