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
                    NavigationLink { CategoryTagManageView() } label: {
                        Label("分类与标签", systemImage: "square.grid.2x2")
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
                        Text(state.store.data.settings.icloudEnabled ? "已开启" : "未开放").foregroundColor(.secondary)
                    }
                    if let t = state.store.data.lastBackupAt {
                        HStack {
                            Label("最近备份", systemImage: "clock.arrow.circlepath")
                            Spacer()
                            Text(t, format: .dateTime.year().month().day().hour().minute()).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("我的")
        }
    }
}

/// 账本切换（顶栏下拉）。
struct LedgerSwitcherView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(state.store.data.ledgers.sorted { $0.sortOrder < $1.sortOrder }) { ledger in
                    Button {
                        state.switchLedger(ledger.id); dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(ledger.name).foregroundColor(.primary)
                                if ledger.archived { Text("已归档").font(.system(size: 11)).foregroundColor(.secondary) }
                            }
                            Spacer()
                            if state.activeLedgerID == ledger.id {
                                Image(systemName: "checkmark").foregroundColor(Design.sage)
                            }
                        }
                    }
                }
            }
            .navigationTitle("切换账本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}

/// 账本管理：创建/改名/排序/归档；空账本删除。
struct LedgerManageView: View {
    @EnvironmentObject var state: AppState
    @State private var newName = ""
    @State private var renaming: Ledger?
    @State private var renameText = ""
    var body: some View {
        List {
            Section("新建账本") {
                HStack {
                    TextField("账本名称（如：旅行）", text: $newName)
                    Button("创建") {
                        if state.perform("账本已创建", { _ = try state.store.createLedger(name: newName) }) {
                            newName = ""
                        }
                    }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("全部账本") {
                ForEach(state.store.data.ledgers.sorted { $0.sortOrder < $1.sortOrder }) { ledger in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(ledger.name)
                            Text(ledger.archived ? "已归档 · 可查看导出，不能新增" : "可用")
                                .font(.system(size: 11)).foregroundColor(.secondary)
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
                                    state.perform("已删除") { try state.store.deleteLedger(ledger.id) }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("我的账本")
        .navigationBarTitleDisplayMode(.inline)
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
        return !hasTxn
    }
}

/// 回收站：按删除日期列表，恢复/永久删除，错误解释。
struct TrashView: View {
    @EnvironmentObject var state: AppState
    @State private var purgeTarget: Transaction?
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
                                .font(.system(size: Design.captionSmall)).foregroundColor(.secondary)
                        }
                        ForEach(items) { t in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(state.store.category(t.categoryID)?.name ?? t.kind.displayName)
                                    Text("\(t.date.year)/\(t.date.month)/\(t.date.day) · ¥\(Money(t.amountCents).yuanDescription)")
                                        .font(.system(size: 11)).foregroundColor(.secondary)
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
    var body: some View {
        List {
            Section("完整备份") {
                Text("备份包含所有账本、账户期初、分类标签、有效与已删除交易、设置和校验清单。")
                    .font(.system(size: Design.captionSmall)).foregroundColor(.secondary)
                Button {
                    if let data = state.exportBackup(), let url = writeTemp(data, name: "yuji-backup.json") {
                        exportURL = url; showShare = true
                    }
                } label: { Label("生成备份文件", systemImage: "square.and.arrow.up") }

                Button { showImporter = true } label: {
                    Label("从备份恢复（先校验再切换）", systemImage: "square.and.arrow.down")
                }
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
            }
            if let t = state.store.data.lastBackupAt {
                Section("状态") {
                    Text("最近备份：\(t.formatted())").font(.system(size: Design.captionSmall))
                }
            }
        }
        .navigationTitle("数据")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                let needsScope = url.startAccessingSecurityScopedResource()
                defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    _ = state.restoreBackup(data)
                } else {
                    state.alertError = "无法读取该文件，请重新选择"
                }
            }
        }
    }
    private func writeTemp(_ data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }
}

/// 外观与反馈偏好：触觉、减弱动态、深浅色。
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Form {
            Section("反馈") {
                Toggle("触觉反馈", isOn: Binding(get: { state.store.data.settings.hapticsEnabled },
                    set: { v in state.perform(nil) { state.store.updateSettings { $0.hapticsEnabled = v } } }))
                Toggle("减弱动态效果", isOn: Binding(get: { state.store.data.settings.reduceMotion },
                    set: { v in state.perform(nil) { state.store.updateSettings { $0.reduceMotion = v } } }))
            }
            Section("外观") {
                Picker("外观", selection: Binding(get: { state.store.data.settings.appearance },
                    set: { v in state.perform(nil) { state.store.updateSettings { $0.appearance = v } } })) {
                    Text("跟随系统").tag(AppearanceMode.system)
                    Text("浅色").tag(AppearanceMode.light)
                    Text("深色").tag(AppearanceMode.dark)
                }
            }
        }
        .navigationTitle("外观与反馈")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 搜索与筛选页（P07）。
struct SearchFilterView: View {
    let ledgerID: EntityID
    var applied: (TransactionFilter) -> Void
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var f = TransactionFilter()
    var body: some View {
        NavigationStack {
            Form {
                Section("关键词") {
                    TextField("备注/分类", text: Binding(get: { f.query ?? "" }, set: { f.query = $0 }))
                }
                Section("类型") {
                    Picker("类型", selection: Binding(get: { f.kind }, set: { f.kind = $0 })) {
                        Text("全部").tag(TransactionKind?.none)
                        Text("支出").tag(TransactionKind?.some(.expense))
                        Text("收入").tag(TransactionKind?.some(.income))
                        Text("退款").tag(TransactionKind?.some(.refund))
                        Text("转账").tag(TransactionKind?.some(.transfer))
                    }
                }
                Section("标签匹配") {
                    Toggle("满足全部标签（默认任一）", isOn: $f.tagMatchAll)
                    NavigationLink("选择标签") {
                        TagMultiSelectInline(ledgerID: ledgerID, selected: $f.tagIDs)
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

struct TagMultiSelectInline: View {
    let ledgerID: EntityID
    @Binding var selected: [EntityID]
    @EnvironmentObject var state: AppState
    var body: some View {
        List {
            ForEach(state.store.tags(in: ledgerID).filter { $0.isLeaf }) { tag in
                Button {
                    if let i = selected.firstIndex(of: tag.id) { selected.remove(at: i) } else { selected.append(tag.id) }
                } label: {
                    HStack {
                        Text(tag.name).foregroundColor(.primary)
                        Spacer()
                        if selected.contains(tag.id) { Image(systemName: "checkmark").foregroundColor(Design.sage) }
                    }
                }
            }
        }
        .navigationTitle("标签")
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
    @State private var error: String?

    private var result: Calculator.Result? { try? Calculator.evaluate(expression) }
    private var cents: Int64? { result?.roundedCents }

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
                        TextField("金额（可算式）", text: $expression)
                            .keyboardType(.numbersAndPunctuation)
                            .font(.system(size: 22, weight: .semibold))
                        if let r = result { Text("¥\(r.roundedDisplay)").foregroundColor(.secondary) }
                        if let e = error { Text(e).foregroundColor(.red).font(.system(size: Design.captionSmall)) }
                        DatePicker("日期", selection: Binding(get: { date.date() },
                            set: { date = Day(from: $0) }), displayedComponents: .date)
                        TextField("备注（可选）", text: $note)
                    }
                    if let f = fromID, let t = toID, let c = cents, f != t {
                        Section("影响预览") {
                            Text("转出账户余额 −¥\(Money(c).yuanDescription)")
                            Text("转入账户余额 +¥\(Money(c).yuanDescription)")
                            Text("收入、支出、预算均不变化").foregroundColor(.secondary).font(.system(size: Design.captionSmall))
                        }
                    }
                }
            }
            .navigationTitle("转账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.bold().disabled(!canSave)
                }
            }
        }
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
