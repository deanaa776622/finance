import SwiftUI

/// Five colors shared by the home glow, allocation bar, and night background.
@Observable
final class Palette {
    var original: Color { didSet { store() } }
    var leverage: Color { didSet { store() } }
    var cash: Color { didSet { store() } }
    var drift: Color { didSet { store() } }
    var ground: Color { didSet { store() } }

    /// Top of the home gradient: the same night, a little brighter.
    var canvasTop: Color { ground.mix(with: .white, by: 0.05) }

    init(
        original: Color = Palette.defaultOriginal,
        leverage: Color = Palette.defaultLeverage,
        cash: Color = Palette.defaultCash,
        drift: Color = Palette.defaultDrift,
        ground: Color = Palette.defaultGround
    ) {
        self.original = original
        self.leverage = leverage
        self.cash = cash
        self.drift = drift
        self.ground = ground
    }

    static func load() -> Palette {
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            return Palette()
        }
        return Palette(
            original: stored.original.color,
            leverage: stored.leverage.color,
            cash: stored.cash.color,
            drift: stored.drift.color,
            ground: stored.ground.color
        )
    }

    func reset() {
        original = Self.defaultOriginal
        leverage = Self.defaultLeverage
        cash = Self.defaultCash
        drift = Self.defaultDrift
        ground = Self.defaultGround
    }

    func glow(for kind: AssetKind, factor: Double) -> Color {
        guard kind.countsTowardAllocation else { return .clear }
        return swatch(for: kind).mix(with: drift, by: factor)
    }

    private func swatch(for kind: AssetKind) -> Color {
        switch kind {
        case .original: original
        case .leverage: leverage
        case .cash: cash
        case .realEstate, .debt: .clear
        }
    }

    private func store() {
        let stored = Stored(
            original: RGB(original),
            leverage: RGB(leverage),
            cash: RGB(cash),
            drift: RGB(drift),
            ground: RGB(ground)
        )
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private static let key = "palette"
    static let defaultOriginal = Color(red: 0.22, green: 0.74, blue: 0.97)
    static let defaultLeverage = Color(red: 0.29, green: 0.87, blue: 0.50)
    static let defaultCash = Color(red: 0.98, green: 0.80, blue: 0.08)
    static let defaultDrift = Color(red: 0.85, green: 0.58, blue: 0.42)
    static let defaultGround = Color(red: 0.03, green: 0.05, blue: 0.10)
}

private struct RGB: Codable {
    var r, g, b: Double
    var color: Color { Color(red: r, green: g, blue: b) }

    init(_ color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        r = Double(resolved.red)
        g = Double(resolved.green)
        b = Double(resolved.blue)
    }
}

private struct Stored: Codable {
    var original, leverage, cash, drift, ground: RGB
}
