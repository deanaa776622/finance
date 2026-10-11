import SwiftUI

struct ColorSettingsView: View {
    @Environment(Palette.self) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Swatch?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    colorRow(.original)
                    colorRow(.leverage)
                    colorRow(.cash)
                } footer: {
                    Text("光球、配置條、目標百分比共用")
                }
                Section {
                    colorRow(.drift)
                } footer: {
                    Text("偏離目標時混進那一桶")
                }
                Section {
                    colorRow(.ground)
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
        .sheet(item: $editing) { swatch in
            ColorDraftPicker(title: swatch.title, initial: swatch.color(in: palette)) { picked in
                swatch.set(picked, on: palette)
            }
        }
    }

    private func colorRow(_ swatch: Swatch) -> some View {
        Button {
            editing = swatch
        } label: {
            HStack {
                Text(swatch.title)
                Spacer()
                Circle()
                    .fill(swatch.color(in: palette))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(.separator, lineWidth: 1))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
    }
}

private enum Swatch: String, Identifiable {
    case original, leverage, cash, drift, ground

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "原型"
        case .leverage: "槓桿"
        case .cash: "現金"
        case .drift: "偏離"
        case .ground: "底"
        }
    }

    private var keyPath: ReferenceWritableKeyPath<Palette, Color> {
        switch self {
        case .original: \.original
        case .leverage: \.leverage
        case .cash: \.cash
        case .drift: \.drift
        case .ground: \.ground
        }
    }

    func color(in palette: Palette) -> Color {
        palette[keyPath: keyPath]
    }

    func set(_ color: Color, on palette: Palette) {
        palette[keyPath: keyPath] = color
    }
}

#Preview {
    ColorSettingsView()
        .environment(Palette())
}
