import SwiftUI

/// Daily iCloud copy of the asset records, and a button to copy them now.
struct BackupSettingsView: View {
    @Environment(Palette.self) private var palette
    @Environment(\.dismiss) private var dismiss
    @AppStorage(ICloudBackup.enabledKey) private var enabled = false
    @AppStorage(ICloudBackup.minutesKey) private var minutes = ICloudBackup.defaultMinutes
    @State private var note = ""
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("每天備份", isOn: $enabled)
                    DatePicker("時間", selection: clock, displayedComponents: .hourAndMinute)
                        .disabled(!enabled)
                } footer: {
                    Text("到了這個時間就把資產紀錄備份到 iCloud。App 開著會準時備份；沒開著時，系統會在之後找時間補上。")
                }
                .listRowBackground(palette.panel)
                Section {
                    Button("立刻備份") { Task { await backup() } }
                        .disabled(working)
                } footer: {
                    Text(note)
                }
                .listRowBackground(palette.panel)
            }
            .tint(palette.ink)
            .palettePanel(palette)
            .navigationTitle("iCloud 備份")
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
        .onAppear { note = lastLine }
        .onChange(of: enabled) { _, _ in ICloudBackup.refreshSchedule() }
        .onChange(of: minutes) { _, _ in ICloudBackup.refreshSchedule() }
    }

    private var clock: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: minutes / 60,
                    minute: minutes % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private var lastLine: String {
        guard let date = ICloudBackup.lastBackup else { return "尚未備份" }
        return "上次備份 \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func backup() async {
        working = true
        defer { working = false }
        switch await ICloudBackup.backupNow() {
        case .success:
            note = lastLine
        case .failure(.noAccount):
            note = "這台裝置還沒登入 iCloud"
        case .failure(.empty):
            note = "還沒有可備份的紀錄"
        case .failure(.busy):
            note = "正在備份"
        case .failure(.failed):
            note = "這次沒有備份成功"
        }
    }
}
