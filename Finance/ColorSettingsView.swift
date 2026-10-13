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
                .listRowBackground(palette.panel)
                Section {
                    colorRow(.drift)
                } footer: {
                    Text("偏離目標時混進那一桶")
                }
                .listRowBackground(palette.panel)
                Section {
                    colorRow(.ground)
                } footer: {
                    Text("首屏、總淨值、總曝險、距離目標。首屏上沿會稍亮，滑出視窗再淺一點")
                }
                .listRowBackground(palette.panel)
                Section {
                    Button("恢復預設") { palette.reset() }
                    Button("儲存主題") {
                        themeName = ""
                        showSave = true
                    }
                    Button("選取主題") { showThemes = true }
                }
                .listRowBackground(palette.panel)
            }
            .palettePanel(palette)
            .navigationTitle("顏色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationBackground(palette.panel)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .background {
            ColorDraftPresenter(
                title: editing?.title,
                initial: editing?.color(in: palette) ?? Palette.defaultOriginal,
                onConfirm: { picked in
                    editing?.set(picked, on: palette)
                    editing = nil
                },
                onCancel: { editing = nil }
            )
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

    func color(in palette: Palette) -> Color {
        switch self {
        case .original: palette.original
        case .leverage: palette.leverage
        case .cash: palette.cash
        case .drift: palette.drift
        case .ground: palette.ground
        }
    }

    func set(_ color: Color, on palette: Palette) {
        switch self {
        case .original: palette.original = color
        case .leverage: palette.leverage = color
        case .cash: palette.cash = color
        case .drift: palette.drift = color
        case .ground: palette.ground = color
        }
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
                        .listRowBackground(palette.panel)
                    }
                    .palettePanel(palette)
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
        .palettePanel(palette)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    ColorSettingsView()
        .environment(Palette())
}
