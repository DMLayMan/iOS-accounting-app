import SwiftUI
import YujiCore

/// 账户列表 + 新增/编辑（期初余额、记账起点、归档）。US03/US04。
struct AccountListView: View {
    @EnvironmentObject var state: AppState
    @State private var editing: Account?
    @State private var showAdd = false
    var body: some View {
        Group {
            if let ledger = state.activeLedger {
                List {
                    Section {
                        Button { showAdd = true } label: {
                            Label("新增账户", systemImage: "plus.circle")
                        }
                    }
                    ForEach(state.store.accounts(in: ledger.id)) { acc in
                        Button { editing = acc } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(acc.name).font(.system(size: Design.bodySize)).foregroundColor(.primary)
                                    if acc.archived { Text("已归档").font(.system(size: 11)).foregroundColor(.secondary) }
                                    Spacer()
                                    Text("¥\(Money(state.store.balance(accountID: acc.id)).yuanDescription)")
                                        .font(.system(size: Design.bodySize, weight: .semibold)).monospacedDigit()
                                        .foregroundColor(.primary)
                                }
                                Text("期初 ¥\(Money(acc.openingBalanceCents).yuanDescription) · 起点 \(acc.startDay.year)/\(acc.startDay.month)/\(acc.startDay.day)")
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .sheet(isPresented: $showAdd) {
                    AccountEditView(ledgerID: ledger.id, account: nil)
                }
                .sheet(item: $editing) { acc in
                    AccountEditView(ledgerID: ledger.id, account: acc)
                }
            }
        }
        .navigationTitle("账户")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AccountEditView: View {
    let ledgerID: EntityID
    let account: Account?
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var openingYuan = ""
    @State private var startDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("如：现金、微信余额", text: $name)
                }
                if account == nil {
                    Section("期初余额（元）") {
                        TextField("0.00", text: $openingYuan).keyboardType(.decimalPad)
                    }
                    Section("记账起点") {
                        DatePicker("起点日期", selection: $startDate, displayedComponents: .date)
                    }
                } else {
                    Section("期初与起点") {
                        Text("修改期初与起点会影响余额核对，提交前请确认。")
                            .font(.system(size: Design.captionSmall)).foregroundColor(.secondary)
                        TextField("期初余额（元）", text: $openingYuan).keyboardType(.decimalPad)
                        DatePicker("记账起点", selection: $startDate, displayedComponents: .date)
                    }
                    if let acc = account {
                        Section {
                            Button(acc.archived ? "恢复为可用" : "归档账户") {
                                state.perform(acc.archived ? "已恢复" : "已归档") {
                                    try state.store.archiveAccount(acc.id, archived: !acc.archived)
                                }
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(account == nil ? "新增账户" : "编辑账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.bold()
                }
            }
            .onAppear {
                if let a = account {
                    name = a.name
                    openingYuan = Money(a.openingBalanceCents).yuanDescription
                    startDate = a.startDay.date()
                } else {
                    startDate = Day(from: Date()).date()
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { state.alertError = "请输入账户名称"; return }
        let openingCents = Money(yuan: Decimal(string: openingYuan) ?? 0).cents
        let start = Day(from: startDate)
        if let a = account {
            _ = state.perform("已保存") {
                try state.store.renameAccount(a.id, name: trimmed)
                try state.store.updateAccountOpening(a.id, openingCents: openingCents, startDay: start)
            }
        } else {
            _ = state.perform("账户已创建") {
                _ = try state.store.createAccount(ledgerID: ledgerID, name: trimmed,
                                                  openingBalanceCents: openingCents, startDay: start)
            }
        }
        dismiss()
    }
}

/// 分类与标签管理（US05/US06）：两级树，新增二级、归档。
struct CategoryTagManageView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Group {
            if let ledger = state.activeLedger {
                List {
                    Section("支出分类") {
                        ForEach(state.store.categories(in: ledger.id, kind: .expense).filter { $0.parentID == nil }) { parent in
                            DisclosureGroup {
                                ForEach(state.store.categories(in: ledger.id, kind: .expense).filter { $0.parentID == parent.id }) { leaf in
                                    leafRow(leaf.name, leaf.archived) {
                                        state.perform(nil) { try state.store.archiveCategory(leaf.id, archived: !leaf.archived) }
                                    }
                                }
                                Button {
                                    addLeaf(title: "新增支出分类", parent: parent, kind: .expense)
                                } label: { Label("新增二级分类", systemImage: "plus") }
                            } label: {
                                Text(parent.name).bold()
                            }
                        }
                    }
                    Section("收入分类") {
                        ForEach(state.store.categories(in: ledger.id, kind: .income).filter { $0.parentID == nil }) { parent in
                            DisclosureGroup {
                                ForEach(state.store.categories(in: ledger.id, kind: .income).filter { $0.parentID == parent.id }) { leaf in
                                    leafRow(leaf.name, leaf.archived) {
                                        state.perform(nil) { try state.store.archiveCategory(leaf.id, archived: !leaf.archived) }
                                    }
                                }
                                Button {
                                    addLeaf(title: "新增收入分类", parent: parent, kind: .income)
                                } label: { Label("新增二级分类", systemImage: "plus") }
                            } label: {
                                Text(parent.name).bold()
                            }
                        }
                    }
                    Section("标签") {
                        ForEach(state.store.tags(in: ledger.id).filter { $0.parentID == nil }) { parent in
                            DisclosureGroup {
                                ForEach(state.store.tags(in: ledger.id).filter { $0.parentID == parent.id }) { leaf in
                                    leafRow(leaf.name, leaf.archived) {
                                        state.perform(nil) { try state.store.archiveTag(leaf.id, archived: !leaf.archived) }
                                    }
                                }
                                Button { addTagLeaf(parent: parent) } label: {
                                    Label("新增二级标签", systemImage: "plus")
                                }
                            } label: {
                                Text(parent.name).bold()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("分类与标签")
        .navigationBarTitleDisplayMode(.inline)
        .alert("新增", isPresented: $showAdd) {
            TextField(newNamePlaceholder, text: $newName)
            Button("取消", role: .cancel) { showAdd = false }
            Button("保存") { confirmAdd() }
        }
    }

    @ViewBuilder
    private func leafRow(_ name: String, _ archived: Bool, toggle: @escaping () -> Void) -> some View {
        HStack {
            Text(name).foregroundColor(archived ? .secondary : .primary)
            if archived { Text("已归档").font(.system(size: 11)).foregroundColor(.secondary) }
            Spacer()
            Button(archived ? "恢复" : "归档", action: toggle).font(.system(size: Design.captionSmall))
        }
    }

    // 新增状态
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newNamePlaceholder = "名称"
    @State private var addContext: AddContext?

    enum AddContext {
        case category(parent: EntityID, kind: TransactionKind)
        case tag(parent: EntityID)
    }

    private func addLeaf(title: String, parent: CategoryNode, kind: TransactionKind) {
        newName = ""; newNamePlaceholder = title; addContext = .category(parent: parent.id, kind: kind); showAdd = true
    }
    private func addTagLeaf(parent: TagNode) {
        newName = ""; newNamePlaceholder = "新增标签"; addContext = .tag(parent: parent.id); showAdd = true
    }
    private func confirmAdd() {
        guard let ledger = state.activeLedger else { return }
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        switch addContext {
        case .category(let parent, let kind):
            _ = state.perform("已添加") {
                _ = try state.store.createCategory(ledgerID: ledger.id, kind: kind, parentID: parent, name: name)
            }
        case .tag(let parent):
            _ = state.perform("已添加") {
                _ = try state.store.createTag(ledgerID: ledger.id, parentID: parent, name: name)
            }
        case .none: break
        }
        showAdd = false
    }
}
