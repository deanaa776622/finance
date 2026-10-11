import SwiftUI

struct ColorSettingsView: View {
    @Environment(Palette.self) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Swatch?
    @State private var showSave = false
    @State private var showThemes = false
    @State private var themeName = ""

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
                    Button("儲存主題") {
                        themeName = ""
                        showSave = true
                    }
                    Button("選取主題") { showThemes = true }
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
        .alert("儲存主題", isPresented: $showSave) {
            TextField("主題名稱", text: $themeName)
            Button("儲存") { palette.saveTheme(named: themeName) }
                .disabled(themeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("取消", role: .cancel) {}
        } message: {
            Text("用目前的五個顏色存成一個主題")
        }
        .sheet(isPresented: $showThemes) {
            ThemeList()
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

private struct ThemeList: View {
    @Environment(Palette.self) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if palette.themes.isEmpty {
                    ContentUnavailableView {
                        Text("尚未儲存主題")
                    }
                } else {
                    List(palette.themes) { theme in
                        Button {
                            palette.apply(theme)
                            dismiss()
                        } label: {
                            Text(theme.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .navigationTitle("選取主題")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }
}

#Preview {
    ColorSettingsView()
        .environment(Palette())
}
