import SwiftUI

struct ColorSettingsView: View {
    @Environment(Palette.self) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var palette = palette
        NavigationStack {
            Form {
                Section {
                    ColorPicker("原型", selection: $palette.original, supportsOpacity: false)
                    ColorPicker("槓桿", selection: $palette.leverage, supportsOpacity: false)
                    ColorPicker("現金", selection: $palette.cash, supportsOpacity: false)
                } footer: {
                    Text("光球、配置條、目標百分比共用")
                }
                Section {
                    ColorPicker("偏離", selection: $palette.drift, supportsOpacity: false)
                } footer: {
                    Text("偏離目標時混進那一桶")
                }
                Section {
                    ColorPicker("底", selection: $palette.ground, supportsOpacity: false)
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
}

#Preview {
    ColorSettingsView()
        .environment(Palette())
}
