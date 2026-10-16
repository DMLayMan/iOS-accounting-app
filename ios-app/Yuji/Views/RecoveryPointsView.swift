import SwiftUI
import YujiCore

struct RecoveryPointsView: View {
    @EnvironmentObject private var state: AppState
    @State private var deleting: AppState.RecoveryPoint?
    @State private var preview: RestorePreview?
    @State private var sharing: AppState.RecoveryPoint?
    var body: some View {
        let points = state.recoveryPoints
        List {
            Section {
                Text("恢复点保存在本机，删除 App 后也会移除。恢复前先预览，清理时只删除选中的副本，当前账本保持不变。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if points.isEmpty { Text("没有本地恢复点").foregroundStyle(.secondary) }
            ForEach(points) { point in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(point.unreadable ? "无法读取的原文件副本" : "替换前的账本")
                        Text(point.createdAt.formatted(date: .numeric, time: .shortened))
                        Text(ByteCountFormatter.string(fromByteCount: Int64(point.bytes), countStyle: .file))
                    }.font(.subheadline)
                    Spacer(minLength: 4)
                    Menu {
                        if !point.unreadable {
                            Button("预览并恢复") {
                                do { preview = try RestorePreview.validated(Data(contentsOf: point.url)) }
                                catch { state.alertError = "无法恢复这个副本，请选择其他备份。原数据保持不变。" }
                            }
                        }
                        Button("导出副本") { sharing = point }
                        Button("删除这个副本", role: .destructive) { deleting = point }
                    } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                        .accessibilityLabel("管理恢复点 " + point.createdAt.formatted())
                }
            }
        }.navigationTitle("本地恢复点").navigationBarTitleDisplayMode(.inline)
            .yujiSheet(item: $preview) { BackupRestoreReview(preview: $0) }
            .yujiSheet(item: $sharing) { ShareSheet(items: [$0.url]) }
            .alert("删除这个恢复点？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("取消", role: .cancel) { deleting = nil }
                Button("删除副本", role: .destructive) {
                    if let point = deleting { state.removeRecoveryPoint(point) }
                    deleting = nil
                }
            } message: { Text("此副本无法恢复。当前账本和其他恢复点保持不变。") }
    }
}
