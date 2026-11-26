import SwiftUI

/// Right half of an unfolded landscape asset page. Trend on top, 原／槓／現 in the middle.
/// The total card is drawn over `cardReserve` by the home screen.
struct AssetSplitColumn: View {
    var buckets: [AssetBucket]
    var cover = false
    var historyKey = ""
    var cardReserve: CGFloat = 0
    var leadingInset: CGFloat = 16
    var trailingInset: CGFloat = 16
    @Environment(Palette.self) private var palette

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                trend
                // Center alignment lands a chart inset low. The extra bottom padding pulls the block back up.
                Color.clear
                    .frame(maxHeight: .infinity)
                    .overlay {
                        ratio.padding(.bottom, AssetListView.chartPanelTop)
                    }
            }
            .padding(.top, AssetListView.chartPanelTop)
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.ground)
            .mask {
                VStack(spacing: 0) {
                    ScrollFade.top
                    Color.black
                }
            }
            Color.clear
                .frame(height: max(0, cardReserve))
                .allowsHitTesting(false)
        }
    }

    private var trend: some View {
        GroupTrendChart(buckets: buckets, cover: cover, historyKey: historyKey)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background { panel }
    }

    private var ratio: some View {
        TargetEditor()
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: GroupCardBackground.radius, style: .continuous)
            .fill(palette.panel)
    }
}
