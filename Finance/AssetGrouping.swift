import Foundation

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
