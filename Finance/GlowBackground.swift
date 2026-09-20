import SwiftUI

/// One soft light per asset kind: size = share of assets, hue = distance from target.
struct GlowOrb: Identifiable {
    let id: String
    let color: Color
    let diameter: CGFloat
    let anchor: UnitPoint
    let sway: CGSize
    let duration: Double
}

extension GlowOrb {
    static func orbs(for portfolio: Portfolio) -> [GlowOrb] {
        AssetKind.allCases.filter(\.countsTowardAllocation).compactMap { kind in
            let share = portfolio.actualPercent(for: kind) / 100
            guard share > 0 else { return nil }
            let layout = kind.glowLayout
            return GlowOrb(
                id: kind.rawValue,
                color: kind.glowColor.mix(with: .driftWarning, by: portfolio.driftFactor(for: kind)),
                diameter: 200 + 260 * share,
                anchor: layout.anchor,
                sway: layout.sway,
                duration: layout.duration
            )
        }
    }
}

private extension Color {
    /// Muted amber — a nudge to look, not an alarm.
    static let driftWarning = Color(red: 0.85, green: 0.58, blue: 0.42)
}

private extension AssetKind {
    /// Same hues as the web prototype: 原型藍 / 槓桿綠 / 現金黃.
    var glowColor: Color {
        switch self {
        case .original: Color(red: 0.22, green: 0.74, blue: 0.97)
        case .leverage: Color(red: 0.29, green: 0.87, blue: 0.50)
        case .cash: Color(red: 0.98, green: 0.80, blue: 0.08)
        case .realEstate, .debt: .clear
        }
    }

    var glowLayout: (anchor: UnitPoint, sway: CGSize, duration: Double) {
        switch self {
        case .original: (UnitPoint(x: 0.22, y: 0.24), CGSize(width: 46, height: 38), 26)
        case .leverage: (UnitPoint(x: 0.80, y: 0.30), CGSize(width: -52, height: 44), 31)
        case .cash: (UnitPoint(x: 0.42, y: 0.80), CGSize(width: 38, height: -46), 35)
        case .realEstate, .debt: (.center, .zero, 30)
        }
    }
}

struct GlowBackground: View {
    let orbs: [GlowOrb]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.06, green: 0.09, blue: 0.16),
                             Color(red: 0.03, green: 0.05, blue: 0.10)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                ForEach(orbs) { orb in
                    Circle()
                        .fill(orb.color)
                        .frame(width: orb.diameter, height: orb.diameter)
                        .blur(radius: 80)
                        .opacity(0.55)
                        .position(
                            x: geo.size.width * orb.anchor.x + (drifting ? orb.sway.width : 0),
                            y: geo.size.height * orb.anchor.y + (drifting ? orb.sway.height : 0)
                        )
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: orb.duration).repeatForever(autoreverses: true),
                            value: drifting
                        )
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { drifting = true }
        .accessibilityHidden(true)
    }
}
