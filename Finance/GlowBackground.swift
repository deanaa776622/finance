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
    /// Full-size orb. Blur uses this same ratio at every size, so a small orb stays as bright.
    static let fullDiameter: CGFloat = 520
    static let fullBlur: CGFloat = 80

    static func orbs(for portfolio: Portfolio, palette: Palette) -> [GlowOrb] {
        AssetKind.allCases.filter(\.countsTowardAllocation).compactMap { kind in
            let achieve = portfolio.achievement(for: kind)
            guard achieve > 0 else { return nil }
            let layout = kind.glowLayout
            return GlowOrb(
                id: kind.rawValue,
                color: palette.glow(for: kind, factor: portfolio.driftFactor(for: kind)),
                diameter: fullDiameter * achieve,
                anchor: layout.anchor,
                points: layout.points,
                duration: layout.duration
            )
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
    /// Home canvas. The glow's area uses the same multiple as this view's area.
    var screen: CGSize
    @Environment(Palette.self) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let home = max(screen.width * screen.height, 1)
            let scale = sqrt(geo.size.width * geo.size.height / home)
            ZStack {
                LinearGradient(
                    colors: [palette.canvasTop, palette.ground],
                    startPoint: .top,
                    endPoint: .bottom
                )

                ForEach(orbs) { orb in
                    let d = orb.diameter * scale
                    let blur = GlowOrb.fullBlur * d / GlowOrb.fullDiameter
                    if reduceMotion || orb.points.count < 2 {
                        glowCircle(orb, diameter: d, blur: blur, alpha: 0.55, point: .zero, in: geo)
                    } else {
                        TimelineView(.animation) { timeline in
                            glowCircle(
                                orb,
                                diameter: d,
                                blur: blur,
                                alpha: 0.55,
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

    /// Stays in the old waypoint box. Two uneven periods, so the path doesn't close quickly.
    private func drift(_ orb: GlowOrb, at date: Date) -> CGSize {
        let points = orb.points
        guard points.count >= 2 else { return .zero }
        let n = Double(points.count)
        let meanX = points.reduce(0.0) { $0 + $1.width } / n
        let meanY = points.reduce(0.0) { $0 + $1.height } / n
        let roomX = min(meanX - points.map(\.width).min()!, points.map(\.width).max()! - meanX)
        let roomY = min(meanY - points.map(\.height).min()!, points.map(\.height).max()! - meanY)
        let t = date.timeIntervalSinceReferenceDate
        let phase = phase(for: orb.id)
        return CGSize(
            width: meanX + roomX * mix(t, period: orb.duration, phase: phase),
            height: meanY + roomY * mix(t, period: orb.duration * 1.414, phase: phase + 1.7)
        )
    }

    /// Weights sum to 1, so the wander stays inside the waypoint box.
    private func mix(_ t: Double, period: Double, phase: Double) -> Double {
        let slow = sin(t / period * 2 * .pi + phase)
        let fast = sin(t / (period * 2.618) * 2 * .pi + phase * 1.3)
        return slow * 0.68 + fast * 0.32
    }

    private func phase(for id: String) -> Double {
        switch id {
        case AssetKind.original.rawValue: 0.6
        case AssetKind.leverage.rawValue: 2.4
        case AssetKind.cash.rawValue: 4.2
        default: 1
        }
    }
}
