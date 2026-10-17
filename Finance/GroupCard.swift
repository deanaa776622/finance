import SwiftUI

/// Title and value row shared by asset groups and the savings groups. No join line.
struct GroupTitle: View {
    var title: String
    var value: String
    var open: Bool
    /// Computed figures stay gray. Asset totals stay the title color.
    var valueMuted = false
    var titleFrame: ((CGRect) -> Void)? = nil
    var action: () -> Void
    @Environment(Palette.self) private var palette
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 20

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .contentTransition(.interpolate)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { titleFrame?($0) }
                Spacer()
                Text(value)
                    .font(.system(size: titleSize))
                    .monospacedDigit()
                    .foregroundStyle(valueMuted ? AnyShapeStyle(palette.quietInk) : AnyShapeStyle(palette.ink))
                    .contentTransition(.numericText())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint(open ? "收合" : "展開")
    }
}

struct GroupCardBackground: View {
    var isFirst: Bool
    var isLast: Bool
    @Environment(Palette.self) private var palette
    static let radius: CGFloat = 26
    static let inset: CGFloat = 16
    /// Matches the group title's leading inset, so the card's left edge lines up with the first glyph.
    static let leading: CGFloat = 32

    var body: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? Self.radius : 0,
            bottomLeadingRadius: isLast ? Self.radius : 0,
            bottomTrailingRadius: isLast ? Self.radius : 0,
            topTrailingRadius: isFirst ? Self.radius : 0,
            style: .continuous
        )
        .fill(palette.ground)
        .padding(.leading, Self.leading)
        .padding(.trailing, Self.inset)
        .allowsHitTesting(false)
    }
}

extension View {
    func groupHeaderChrome() -> some View {
        modifier(GroupHeaderChrome())
    }

    func groupCardRow(isFirst: Bool, isLast: Bool) -> some View {
        modifier(GroupCardRow(isFirst: isFirst, isLast: isLast))
    }

    func groupPlainRow() -> some View {
        modifier(GroupPlainRow())
    }
}

private struct GroupHeaderChrome: ViewModifier {
    @Environment(Palette.self) private var palette

    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 18, leading: 32, bottom: 8, trailing: 32))
            .listRowSeparator(.hidden)
            .listRowBackground(palette.ground)
            .textCase(nil)
    }
}

private struct GroupCardRow: ViewModifier {
    var isFirst: Bool
    var isLast: Bool

    func body(content: Content) -> some View {
        content
            .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(
                top: 0,
                leading: GroupCardBackground.leading,
                bottom: 0,
                trailing: GroupCardBackground.inset
            ))
            .listRowSeparator(.hidden)
            .listRowBackground(GroupCardBackground(isFirst: isFirst, isLast: isLast))
    }
}

private struct GroupPlainRow: ViewModifier {
    @Environment(Palette.self) private var palette

    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 10, leading: 32, bottom: 10, trailing: 32))
            .listRowSeparator(.hidden)
            .listRowBackground(palette.ground)
    }
}
