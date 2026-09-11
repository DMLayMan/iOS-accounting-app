import SwiftUI
import UIKit
import UniformTypeIdentifiers
import YujiCore

/// 我的：账本管理、账户、回收站、数据备份/导出、偏好、存储状态。
struct MeView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("账本") {
                    NavigationLink { LedgerManageView() } label: {
                        Label("我的账本", systemImage: "books.vertical")
                    }
                    NavigationLink { AccountListView() } label: {
                        Label("账户", systemImage: "creditcard")
                    }
                    NavigationLink { CategoryManageView() } label: {
                        Label("分类管理", systemImage: "square.grid.2x2")
                    }
                }
                Section("整理") {
                    NavigationLink { TrashView() } label: {
                        Label("最近删除", systemImage: "trash")
                    }
                }
                Section("数据") {
                    NavigationLink { DataManagementView() } label: {
                        Label("备份、恢复与导出", systemImage: "externaldrive")
                    }
                }
                Section("偏好") {
                    NavigationLink { SettingsView() } label: {
                        Label("外观与反馈", systemImage: "slider.horizontal.3")
                    }
                }
                Section("存储") {
                    HStack {
                        Label("数据位置", systemImage: "internaldrive")
                        Spacer()
                        Text("本机本地").foregroundColor(.secondary)
                    }
                    HStack {
                        Label("iCloud 同步", systemImage: "icloud")
                        Spacer()
                        Text("未开放").foregroundColor(.secondary)
                    }
                    if let t = state.store.data.lastBackupAt {
                        HStack {
                            Label("最近生成备份", systemImage: "clock.arrow.circlepath")
                            Spacer()
                            Text(t, format: .dateTime.year().month().day().hour().minute()).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("我的").navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// 账本切换与新建共用一个入口，选择成功后才退出。
struct LedgerSwitcherView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(state.store.data.ledgers.sorted { $0.sortOrder < $1.sortOrder }) { ledger in
                    Button {
                        if state.switchLedger(ledger.id) { dismiss() }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(ledger.name).foregroundColor(.primary)
                                if ledger.archived { Text("已归档").font(.caption).foregroundColor(.secondary) }
                            }
                            Spacer()
                            if state.activeLedgerID == ledger.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }.accessibilityAddTraits(state.activeLedgerID == ledger.id ? [.isSelected] : [])
                        .accessibilityIdentifier("ledger.choose.\(ledger.id.raw)")
                }
                Section {
                    NavigationLink {
                        LedgerCreateView(completion: { dismiss() })
                    } label: { Label("新建账本", systemImage: "plus") }
                        .accessibilityIdentifier("ledger.switcherCreate")
                    NavigationLink("管理账本", destination: LedgerManageView())
                }
            }
            .navigationTitle("切换账本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

/// 账本管理：创建/改名/排序/归档；空账本删除。
struct LedgerManageView: View {
    @EnvironmentObject var state: AppState
    @State private var renaming: Ledger?
    @State private var deleting: Ledger?
    @State private var renameText = ""
    var body: some View {
        List {
            Section("新建账本") {
                NavigationLink { LedgerCreateView() } label: { Label("新建账本", systemImage: "plus") }
            }
            Section("全部账本") {
                ForEach(state.store.data.ledgers.sorted { $0.sortOrder < $1.sortOrder }) { ledger in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(ledger.name)
                            Text(ledger.archived ? "已归档 · 可查看导出，不能新增" : "可用")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button("改名") { renaming = ledger; renameText = ledger.name }
                            Button(ledger.archived ? "恢复可用" : "归档") {
                                state.perform(ledger.archived ? "已恢复" : "已归档") {
                                    try state.store.archiveLedger(ledger.id, archived: !ledger.archived)
                                }
                            }
                            if isDeletable(ledger) {
                                Button("删除空账本", role: .destructive) {
                                    deleting = ledger
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44)
                        }.accessibilityLabel("管理 " + ledger.name)
                    }
                }
            }
        }
        .navigationTitle("我的账本")
        .navigationBarTitleDisplayMode(.inline)
        .alert("删除这个空账本？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除", role: .destructive) {
                if let ledger = deleting { state.perform("已删除") { try state.store.deleteLedger(ledger.id) } }
                deleting = nil
            }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("账本中的账户、分类、预算和未保存草稿也会删除。此操作无法撤销。") }
        .alert("改名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) { renaming = nil }
            Button("保存") {
                if let l = renaming {
                    state.perform("已改名") { try state.store.renameLedger(l.id, name: renameText) }
                }
                renaming = nil
            }
        }
    }
    private func isDeletable(_ l: Ledger) -> Bool {
        let hasTxn = state.store.data.transactions.contains { $0.ledgerID == l.id }
        return !hasTxn && (l.archived || state.store.data.ledgers.filter { !$0.archived }.count > 1)
    }
}

/// 回收站：按删除日期列表，恢复/永久删除，错误解释。
struct TrashView: View {
    @EnvironmentObject var state: AppState
    @State private var purgeTarget: YujiCore.Transaction?
    var body: some View {
        Group {
            if let ledger = state.activeLedger {
                let items = state.store.trashedTransactions(in: ledger.id)
                    .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
                if items.isEmpty {
                    QuietEmptyView(message: "回收站为空")
                } else {
                    List {
                        Section {
                            Text("删除的记录保留在此，恢复时会重新检查退款额度与关联。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        ForEach(items) { t in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(state.store.category(t.categoryID)?.name ?? t.kind.displayName)
                                    Text("\(t.date.year)/\(t.date.month)/\(t.date.day) · ¥\(Money(t.amountCents).yuanDescription)")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("恢复") { state.restore(t.id) }.buttonStyle(.bordered)
                                Button(role: .destructive) { purgeTarget = t } label: {
                                    Image(systemName: "trash")
                                }.buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("最近删除")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("永久删除后无法恢复", isPresented: Binding(get: { purgeTarget != nil },
                            set: { if !$0 { purgeTarget = nil } }), titleVisibility: .visible) {
            Button("永久删除", role: .destructive) {
                if let t = purgeTarget { state.purge(t.id) }
                purgeTarget = nil
            }
            Button("取消", role: .cancel) { purgeTarget = nil }
        }
    }
}

/// 数据管理：备份/恢复/CSV 导出。
struct DataManagementView: View {
    @EnvironmentObject var state: AppState
    @State private var showShare = false
    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var restorePreview: RestorePreview?
    var body: some View {
        List {
            Section("完整备份") {
                Text("完整保存全部账本、账户、分类、草稿与历史流水。请把生成的文件存到安全的位置。")
                    .font(.caption).foregroundColor(.secondary)
                Button {
                    if let data = state.exportBackup(), let url = writeTemp(data, name: "yuji-backup.json") {
                        state.markBackupGenerated(); exportURL = url; showShare = true
                    }
                } label: { Label("生成备份文件", systemImage: "square.and.arrow.up") }
                    .disabled(state.storageFailure != nil)

                Button { showImporter = true } label: {
                    Label("选择备份恢复", systemImage: "square.and.arrow.down")
                }
            }
            if let url = state.recoveryBackupURL, FileManager.default.fileExists(atPath: url.path) {
                Section {
                    Button("恢复到上次替换前") {
                        do { try prepareRestore(Data(contentsOf: url)) }
                        catch { state.alertError = "无法读取恢复点：\(error.localizedDescription)" }
                    }
                } footer: { Text("每次恢复前，自动保留一份替换前的数据。") }
            }
            Section("CSV 导出") {
                Button {
                    if let ledger = state.activeLedger {
                        let csv = state.exportCSV(ledgerID: ledger.id)
                        if let url = writeTemp(Data(csv.utf8), name: "yuji-\(ledger.name).csv") {
                            exportURL = url; showShare = true
                        }
                    }
                } label: { Label("导出当前账本 CSV", systemImage: "tablecells") }
                    .disabled(state.storageFailure != nil || state.activeLedger == nil)
            }
            if let t = state.store.data.lastBackupAt {
                Section("状态") {
                    Text("最近生成：\(t.formatted())").font(.caption)
                    Text("生成后请在分享面板中存储文件。这里的时间不代表已保存到外部位置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["YUJI_RESTORE_PREVIEW_TEST"] == "1",
               ProcessInfo.processInfo.environment["YUJI_STRESS_SESSION"] != nil,
               let bytes = state.exportBackup() { try? prepareRestore(bytes) }
            #endif
        }
        .navigationTitle("数据")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(item: $restorePreview) { preview in
            BackupRestoreReview(preview: preview)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                let needsScope = url.startAccessingSecurityScopedResource()
                defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    do { try prepareRestore(data) }
                    catch let error as BackupService.RestoreError { state.alertError = error.message }
                    catch { state.alertError = "无法识别此备份，请选择余记生成的备份文件。" }
                } else {
                    state.alertError = "无法读取该文件，请重新选择"
                }
            }
        }
    }
    private func prepareRestore(_ bytes: Data) throws {
        let backup = try BackupService.decode(bytes)
        _ = try BackupService.validate(backup: backup)
        restorePreview = RestorePreview(bytes: bytes, backup: backup)
    }
    private func writeTemp(_ data: Data, name: String) -> URL? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let filename = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let url = directory.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic); return url
        } catch {
            state.alertError = "文件未生成，请检查可用空间后重试。"; return nil
        }
    }
}

/// 外观与反馈偏好：触觉、减弱动态、深浅色。
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var showingColorPicker = false
    var body: some View {
        Form {
            ThemeSettingsSections { showingColorPicker = true }
            Section("反馈") {
                Toggle("触觉反馈", isOn: Binding(get: { state.store.data.settings.hapticsEnabled },
                    set: { v in state.perform(nil) { state.store.updateSettings { $0.hapticsEnabled = v } } }))
                Toggle("减弱动态效果", isOn: Binding(get: { state.store.data.settings.reduceMotion },
                    set: { v in state.perform(nil) { state.store.updateSettings { $0.reduceMotion = v } } }))
            }
        }
        .navigationTitle("外观与反馈").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("theme.settings")
        .background(NativeThemeColorPicker(isPresented: $showingColorPicker, rgb: state.store.data.settings.accentRGB) { rgb in
            state.perform { state.store.updateSettings { $0.accentTheme = .custom; $0.customAccentRGB = rgb } }
        })
    }
}

/// 搜索与筛选页（P07）。
struct SearchFilterView: View {
    let ledgerID: EntityID
    var applied: (TransactionFilter) -> Void
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var f = TransactionFilter()
    init(ledgerID: EntityID, initial: TransactionFilter? = nil, applied: @escaping (TransactionFilter) -> Void) {
        self.ledgerID = ledgerID
        self.applied = applied
        _f = State(initialValue: initial ?? TransactionFilter())
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("关键词") {
                    TextField("搜索一级或二级分类", text: Binding(get: { f.query ?? "" }, set: { f.query = $0 }))
                        .accessibilityIdentifier("feed.query").submitLabel(.search)
                        .onSubmit { applied(f); dismiss() }
                }
                Section("类型") {
                    Picker("类型", selection: Binding(get: { f.kind }, set: { f.kind = $0; f.categoryID = nil })) {
                        Text("全部").tag(TransactionKind?.none)
                        Text("支出").tag(TransactionKind?.some(.expense))
                        Text("收入").tag(TransactionKind?.some(.income))
                        Text("退款").tag(TransactionKind?.some(.refund))
                        Text("转账").tag(TransactionKind?.some(.transfer))
                    }
                }
                Section("分类") {
                    Picker("按分类筛选", selection: $f.categoryID) {
                        Text("全部分类").tag(EntityID?.none)
                        ForEach(state.store.data.categories.filter { $0.ledgerID == ledgerID &&
                            (f.kind == nil || f.kind == .refund && $0.kind == .expense || f.kind == $0.kind) }) { category in
                            Text(state.store.categoryPath(category.id)).tag(EntityID?.some(category.id))
                        }
                    }
                }
                Section {
                    Button("重置筛选") { f = TransactionFilter() }
                    Button("应用筛选") { applied(f); dismiss() }.bold()
                }
            }
            .navigationTitle("搜索与筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

/// 转账页（P06）：转出→转入、金额、日期、影响摘要。
struct TransferView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var fromID: EntityID?
    @State private var toID: EntityID?
    @State private var expression = ""
    @State private var date = Day(from: Date())
    @State private var note = ""
    @State private var exitRequested = false
    @State private var initialized = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var result: Calculator.Result? { try? Calculator.evaluate(expression) }
    private var cents: Int64? { result?.roundedCents }

    private var hasChanges: Bool { !expression.isEmpty || !note.isEmpty || fromID != nil || toID != nil || date != state.today }
    var body: some View {
        NavigationStack {
            Form {
                if let ledger = state.activeLedger {
                    let accounts = state.store.accounts(in: ledger.id, includeArchived: false)
                    Section("账户") {
                        Picker("转出账户", selection: $fromID) {
                            Text("选择").tag(EntityID?.none)
                            ForEach(accounts) { Text($0.name).tag(EntityID?.some($0.id)) }
                        }
                        Picker("转入账户", selection: $toID) {
                            Text("选择").tag(EntityID?.none)
                            ForEach(accounts) { Text($0.name).tag(EntityID?.some($0.id)) }
                        }
                    }
                    Section("金额") {
                        TextField("金额（可算式）", text: $expression).focused($focused)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.system(size: 22, weight: .semibold))
                        if let r = result { Text("¥\(r.roundedDisplay)").foregroundColor(.secondary) }
                        if let e = error { Text(e).foregroundColor(.red).font(.caption) }
                        DatePicker("日期", selection: Binding(get: { date.date() },
                            set: { date = Day(from: $0) }), displayedComponents: .date)
                        TextField("备注（可选）", text: $note).focused($focused)
                    }
                    if let f = fromID, let t = toID, let c = cents, f != t {
                        Section("影响预览") {
                            Text("转出账户余额 −¥\(Money(c).yuanDescription)")
                            Text("转入账户余额 +¥\(Money(c).yuanDescription)")
                            Text("收入、支出、预算均不变化").foregroundColor(.secondary).font(.caption)
                        }
                    }
                }
            }
            .onAppear { if !initialized { date = state.today; initialized = true } }
            .navigationTitle("转账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { focused = false; if hasChanges { exitRequested = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(result?.saveActionTitle ?? "保存") { save() }.bold().disabled(!canSave)
                }
            }
        }.presentationDetents([.fraction(0.7), .large]).presentationDragIndicator(.visible).modifier(CleanSheetSurface()).modifier(FormExitGuard(isDirty: hasChanges, requested: $exitRequested))
    }
    private var canSave: Bool {
        guard let f = fromID, let t = toID, let c = cents, f != t, c > 0 else { return false }
        return Money(c).isWithinPositiveProductRange
    }
    private func save() {
        guard let ledger = state.activeLedger, let f = fromID, let t = toID, let c = cents else { return }
        let ok = state.addTransfer(amountCents: c, date: date, from: f, to: t, note: note, ledgerID: ledger.id)
        if ok { dismiss() } else { error = state.alertError }
    }
}

/// UIActivityViewController 包装（分享备份/CSV 文件）。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
