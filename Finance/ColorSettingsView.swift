import SwiftUI

struct ColorSettingsView: View {
    @Environment(Palette.self) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var palette = palette
        NavigationStack {
            Form {
                Section {
                    colorRow("原型", selection: $palette.original)
                    colorRow("槓桿", selection: $palette.leverage)
                    colorRow("現金", selection: $palette.cash)
                } footer: {
                    Text("光球、配置條、目標百分比共用")
                }
                Section {
                    colorRow("偏離", selection: $palette.drift)
                } footer: {
                    Text("偏離目標時混進那一桶")
                }
                Section {
                    colorRow("底", selection: $palette.ground)
                } footer: {
                    Text("首屏夜色，上沿會稍亮")
                }
                Section {
                    Button("恢復預設") { palette.reset() }
                }
            }
            .navigationTitle("顏色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(.systemGroupedBackground))
        .presentationDragIndicator(.visible)
    }

    /// Plain swatch painted over the system well. The well still receives the tap.
    private func colorRow(_ title: String, selection: Binding<Color>) -> some View {
        HStack {
            Text(title)
                .accessibilityHidden(true)
            Spacer()
            ColorPicker(title, selection: selection, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28, height: 28)
                .overlay {
                    Circle()
                        .fill(selection.wrappedValue)
                        .overlay(Circle().strokeBorder(.separator, lineWidth: 1))
                        .allowsHitTesting(false)
                }
        }
    }
}

#Preview {
    ColorSettingsView()
        .environment(Palette())
}
