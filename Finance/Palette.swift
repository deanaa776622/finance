import SwiftUI

/// Bucket colors, drift, and the night background of home, net worth, exposure, and savings.
@Observable
final class Palette {
    var original: Color { didSet { store() } }
    var leverage: Color { didSet { store() } }
    var cash: Color { didSet { store() } }
    var realEstate: Color { didSet { store() } }
    var debt: Color { didSet { store() } }
    var drift: Color { didSet { store() } }
    var ground: Color { didSet { store() } }
    /// Nil until the user picks a text color. Until then, ink follows the night color.
    private var inkChoice: Color? { didSet { store() } }

    /// Text that has no color of its own. Secondary copy is the same ink, quieter.
    var ink: Color {
        get { inkChoice ?? Self.automaticInk(on: ground) }
        set { inkChoice = newValue }
    }

    var quietInk: Color { ink.opacity(0.62) }

    /// Top of the home gradient: the same night, a little brighter.
    var canvasTop: Color { ground.mix(with: .white, by: 0.05) }

    /// Sliding sheets: the same night, a step lighter than the page.
    var panel: Color { ground.mix(with: .white, by: 0.10) }

    /// Light ground gets dark text and system surfaces; dark ground stays in night mode.
    var colorScheme: ColorScheme {
        ground.relativeLuminance(scheme: .dark) > 0.179 ? .light : .dark
    }

    init(
        original: Color = Palette.defaultOriginal,
        leverage: Color = Palette.defaultLeverage,
        cash: Color = Palette.defaultCash,
        realEstate: Color = Palette.defaultRealEstate,
        debt: Color = Palette.defaultDebt,
        drift: Color = Palette.defaultDrift,
        ground: Color = Palette.defaultGround,
        ink: Color? = nil
    ) {
        self.original = original
        self.leverage = leverage
        self.cash = cash
        self.realEstate = realEstate
        self.debt = debt
        self.drift = drift
        self.ground = ground
        self.inkChoice = ink
        themes = Self.loadThemes()
    }

    private(set) var themes: [PaletteTheme] = []

    func saveTheme(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let colors = Stored(
            original: RGB(original),
            leverage: RGB(leverage),
            cash: RGB(cash),
            drift: RGB(drift),
            ground: RGB(ground),
            realEstate: RGB(realEstate),
            debt: RGB(debt),
            ink: RGB(ink)
        )
        if let index = themes.firstIndex(where: { $0.name == name }) {
            themes[index].colors = colors
        } else {
            themes.append(PaletteTheme(id: UUID(), name: name, colors: colors))
        }
        storeThemes()
    }

    func apply(_ theme: PaletteTheme) {
        original = theme.colors.original.color
        leverage = theme.colors.leverage.color
        cash = theme.colors.cash.color
        realEstate = theme.colors.realEstate?.color ?? Self.defaultRealEstate
        debt = theme.colors.debt?.color ?? Self.defaultDebt
        drift = theme.colors.drift.color
        ground = theme.colors.ground.color
        inkChoice = theme.colors.ink?.color
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
            realEstate: stored.realEstate?.color ?? Palette.defaultRealEstate,
            debt: stored.debt?.color ?? Palette.defaultDebt,
            drift: stored.drift.color,
            ground: stored.ground.color,
            ink: stored.ink?.color
        )
    }

    func reset() {
        original = Self.defaultOriginal
        leverage = Self.defaultLeverage
        cash = Self.defaultCash
        realEstate = Self.defaultRealEstate
        debt = Self.defaultDebt
        drift = Self.defaultDrift
        ground = Self.defaultGround
        inkChoice = nil
    }

    func glow(for kind: AssetKind, factor: Double) -> Color {
        let color = swatch(for: kind)
        guard kind.countsTowardAllocation else { return color }
        return color.mix(with: drift, by: factor)
    }

    private func swatch(for kind: AssetKind) -> Color {
        switch kind {
        case .original: original
        case .leverage: leverage
        case .cash: cash
        case .realEstate: realEstate
        case .debt: debt
        }
    }

    private func store() {
        let stored = Stored(
            original: RGB(original),
            leverage: RGB(leverage),
            cash: RGB(cash),
            drift: RGB(drift),
            ground: RGB(ground),
            realEstate: RGB(realEstate),
            debt: RGB(debt),
            ink: inkChoice.map { RGB($0) }
        )
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private static func loadThemes() -> [PaletteTheme] {
        guard let data = UserDefaults.standard.data(forKey: themesKey),
              let themes = try? JSONDecoder().decode([PaletteTheme].self, from: data) else {
            return []
        }
        return themes
    }

    private func storeThemes() {
        if let data = try? JSONEncoder().encode(themes) {
            UserDefaults.standard.set(data, forKey: Self.themesKey)
        }
    }

    private static let key = "palette"
    private static let themesKey = "palette.themes"
    static let defaultOriginal = Color(red: 0.22, green: 0.74, blue: 0.97)
    static let defaultLeverage = Color(red: 0.29, green: 0.87, blue: 0.50)
    static let defaultCash = Color(red: 0.98, green: 0.80, blue: 0.08)
    static let defaultRealEstate = Color(red: 0.93, green: 0.94, blue: 0.95)
    static let defaultDebt = Color(red: 0.58, green: 0.64, blue: 0.72)
    static let defaultDrift = Color(red: 0.85, green: 0.58, blue: 0.42)
    static let defaultGround = Color(red: 0.03, green: 0.05, blue: 0.10)

    private static func automaticInk(on ground: Color) -> Color {
        ground.relativeLuminance(scheme: .dark) > 0.179 ? .black : .white
    }
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
    /// Absent in palettes saved before these two colors existed.
    var realEstate: RGB?
    var debt: RGB?
    /// Absent until the user chooses a text color.
    var ink: RGB?
}

struct PaletteTheme: Identifiable, Codable {
    var id: UUID
    var name: String
    fileprivate var colors: Stored
}

extension View {
    /// Sheet chrome and rows, one step lighter than the page.
    func palettePanel(_ palette: Palette) -> some View {
        scrollContentBackground(.hidden)
            .background(palette.panel)
            .listRowBackground(palette.panel)
            .toolbarBackground(palette.panel, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .presentationBackground(palette.panel)
    }
}

extension Color {
    /// Black or white text, whichever contrasts with this fill. The switch is the WCAG crossover.
    func readable(on background: Color, scheme: ColorScheme) -> Color {
        guard contrast(against: background, scheme: scheme) < 3 else { return self }
        let ink: Color = background.relativeLuminance(scheme: scheme) > 0.179 ? .black : .white
        var amount = 0.25
        var mixed = self
        for _ in 0..<5 {
            mixed = mix(with: ink, by: amount)
            if mixed.contrast(against: background, scheme: scheme) >= 3 { return mixed }
            amount += 0.15
        }
        return mixed
    }

    func relativeLuminance(scheme: ColorScheme) -> Double {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let resolved = resolve(in: environment)
        func linear(_ channel: Float) -> Double {
            let value = Double(channel)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let red = linear(resolved.red)
        let green = linear(resolved.green)
        let blue = linear(resolved.blue)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private func contrast(against other: Color, scheme: ColorScheme) -> Double {
        let lighter = max(relativeLuminance(scheme: scheme), other.relativeLuminance(scheme: scheme))
        let darker = min(relativeLuminance(scheme: scheme), other.relativeLuminance(scheme: scheme))
        return (lighter + 0.05) / (darker + 0.05)
    }
}
