import SwiftUI

/// One soft light per bucket: size = progress toward that slice of 目標總額, hue = allocation drift.
struct GlowOrb: Identifiable {
    let id: String
    let color: Color
    let diameter: CGFloat
    let anchor: UnitPoint
    let points: [CGSize]
    let duration: Double
}

extension GlowOrb {
    static func orbs(for portfolio: Portfolio) -> [GlowOrb] {
        AssetKind.allCases.filter(\.countsTowardAllocation).compactMap { kind in
            let achieve = portfolio.achievement(for: kind)
            guard achieve > 0 else { return nil }
            let layout = kind.glowLayout
            return GlowOrb(
                id: kind.rawValue,
                color: portfolio.glowColor(for: kind),
                diameter: 520 * achieve,
                anchor: layout.anchor,
                points: layout.points,
                duration: layout.duration
            )
        }
    }
}

private extension Color {
    /// Muted amber — a nudge to look, not an alarm.
    static let driftWarning = Color(red: 0.85, green: 0.58, blue: 0.42)
}

extension Portfolio {
    /// Home orb hue for this bucket, including the drift tint.
    func glowColor(for kind: AssetKind) -> Color {
        kind.glowColor.mix(with: .driftWarning, by: driftFactor(for: kind))
    }
}

extension AssetKind {
    /// 原型藍 / 槓桿綠 / 現金黃. Same hues as the web prototype.
    var glowColor: Color {
        switch self {
        case .original: Color(red: 0.22, green: 0.74, blue: 0.97)
        case .leverage: Color(red: 0.29, green: 0.87, blue: 0.50)
        case .cash: Color(red: 0.98, green: 0.80, blue: 0.08)
        case .realEstate, .debt: .clear
        }
    }
}

private extension AssetKind {
    var glowLayout: (anchor: UnitPoint, points: [CGSize], duration: Double) {
        switch self {
        case .original: (UnitPoint(x: 0.22, y: 0.24), [
            .zero,
            CGSize(width: 0.36, height: 0.12),
            CGSize(width: 0.13, height: 0.21),
            CGSize(width: -0.25, height: 0.09),
        ], 15)
        case .leverage: (UnitPoint(x: 0.80, y: 0.30), [
            .zero,
            CGSize(width: -0.41, height: 0.14),
            CGSize(width: -0.18, height: -0.12),
        ], 20)
        case .cash: (UnitPoint(x: 0.42, y: 0.80), [
            .zero,
            CGSize(width: 0.25, height: -0.14),
            CGSize(width: -0.31, height: -0.09),
            CGSize(width: 0.20, height: 0.06),
        ], 24)
        case .realEstate, .debt: (.center, [.zero], 30)
        }
    }
}

struct GlowBackground: View {
    let orbs: [GlowOrb]
    /// 0 = full-screen glow, 1 = the short docked card.
    var compact: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let t = min(1, max(0, compact))
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.06, green: 0.09, blue: 0.16),
                             Color(red: 0.03, green: 0.05, blue: 0.10)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                ForEach(orbs) { orb in
                    let d = orb.diameter + (min(orb.diameter, geo.size.width * 0.55) - orb.diameter) * t
                    let blur = 80 + (40 - 80) * t
                    let alpha = 0.55 + (0.62 - 0.55) * t
                    if reduceMotion || orb.points.count < 2 {
                        glowCircle(orb, diameter: d, blur: blur, alpha: alpha, point: .zero, in: geo)
                    } else {
                        TimelineView(.animation) { timeline in
                            glowCircle(
                                orb,
                                diameter: d,
                                blur: blur,
                                alpha: alpha,
                                point: drift(orb, at: timeline.date),
                                in: geo
                            )
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func glowCircle(
        _ orb: GlowOrb,
        diameter: CGFloat,
        blur: CGFloat,
        alpha: Double,
        point: CGSize,
        in geo: GeometryProxy
    ) -> some View {
        Circle()
            .fill(orb.color)
            .frame(width: diameter, height: diameter)
            .blur(radius: blur)
            .opacity(alpha)
            .position(
                x: geo.size.width * (orb.anchor.x + point.width),
                y: geo.size.height * (orb.anchor.y + point.height)
            )
    }

    /// Waypoints are fractions of the current view, so the path scales with the card while dragging.
    private func drift(_ orb: GlowOrb, at date: Date) -> CGSize {
        let points = orb.points
        let count = points.count
        guard count >= 2 else { return .zero }
        let cycle = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: orb.duration) / orb.duration
        let scaled = cycle * Double(count)
        let index = Int(scaled) % count
        let local = scaled - Double(Int(scaled))
        let eased = local * local * (3 - 2 * local)
        let from = points[index]
        let to = points[(index + 1) % count]
        return CGSize(
            width: from.width + (to.width - from.width) * eased,
            height: from.height + (to.height - from.height) * eased
        )
    }
}
