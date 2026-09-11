import SwiftUI
import YujiCore

struct RestorePreview: Identifiable {
    let id = UUID()
    let bytes: Data
    let backup: BackupService.BackupFile
}

struct BackupRestoreReview: View {
    let preview: RestorePreview
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("备份已通过校验", systemImage: "checkmark.shield")
                        .font(.headline).foregroundStyle(.tint)
                    Text(preview.backup.createdAt.formatted(date: .numeric, time: .shortened))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("将恢复") {
                    LabeledContent("账本", value: "\(preview.backup.checksum.ledgerCount) 本")
                    LabeledContent("有效流水", value: "\(preview.backup.checksum.activeTransactionCount) 条")
                    LabeledContent("最近删除", value: "\(preview.backup.checksum.trashedTransactionCount) 条")
                }
                Section {
                    Text(state.storageFailure == nil
                         ? "这会替换当前全部 \(state.store.data.ledgers.count) 本账本及 \(state.store.data.transactions.count) 条流水。"
                         : "这会用备份恢复本地账本。")
                    Text(state.storageFailure == nil
                         ? "替换前会自动保留当前数据，可在数据页恢复。"
                         : "替换前会保留无法读取的原文件，供后续排查。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("确认替换全部数据") {
                    if state.restoreBackup(preview.bytes) { dismiss() } else { error = state.alertError }
                }.buttonStyle(SolidActionStyle()).accessibilityIdentifier("backup.confirmRestore")
                    .padding(20).background(Color(.systemBackground))
            }
            .navigationTitle("恢复备份").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }.presentationDetents([.fraction(0.7), .large]).presentationDragIndicator(.visible).modifier(CleanSheetSurface())
    }
}
