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
                                    Text(acc.name).font(.body).foregroundColor(.primary)
                                    if acc.archived { Text("已归档").font(.caption).foregroundColor(.secondary) }
                                    Spacer()
                                    Text("¥\(Money(state.store.balance(accountID: acc.id)).yuanDescription)")
                                        .font(.body.weight(.semibold)).monospacedDigit()
                                        .foregroundColor(.primary)
                                }
                                Text("期初 ¥\(Money(acc.openingBalanceCents).yuanDescription) · 起点 \(acc.startDay.year)/\(acc.startDay.month)/\(acc.startDay.day)")
                                    .font(.caption).foregroundColor(.secondary)
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
    @State private var exitRequested = false
    @State private var error: String?
    @State private var loaded = false
    @FocusState private var focused: Bool

    private var hasChanges: Bool {
        loaded && (name != (account?.name ?? "") || openingYuan != (account.map { Money($0.openingBalanceCents).inputString } ?? "") || Day(from: startDate) != (account?.startDay ?? state.today))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("如：现金、微信余额", text: $name).focused($focused).accessibilityIdentifier("account.name")
                }
                if account == nil {
                    Section("期初余额（元）") {
                        TextField("0.00", text: $openingYuan).keyboardType(.numbersAndPunctuation).focused($focused).accessibilityIdentifier("account.opening")
                    }
                    Section("记账起点") {
                        DatePicker("起点日期", selection: $startDate, displayedComponents: .date)
                    }
                } else {
                    Section("期初与起点") {
                        Text("修改期初与起点会影响余额核对，提交前请确认。")
                            .font(.caption).foregroundColor(.secondary)
                        TextField("期初余额（元）", text: $openingYuan).keyboardType(.numbersAndPunctuation).focused($focused).accessibilityIdentifier("account.opening")
                        DatePicker("记账起点", selection: $startDate, displayedComponents: .date)
                    }
                    if let acc = account {
                        Section {
                            Button(acc.archived ? "恢复为可用" : "归档账户") {
                                if state.perform(acc.archived ? "已恢复" : "已归档", {
                                    try state.store.archiveAccount(acc.id, archived: !acc.archived)
                                }) { dismiss() } else { error = state.alertError }
                            }
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.subheadline).accessibilityIdentifier("account.error") } }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(account == nil ? "新增账户" : "编辑账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { focused = false; if hasChanges { exitRequested = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.bold().disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("account.save")
                }
            }
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成输入") { focused = false } } }
            .onAppear {
                guard !loaded else { return }; loaded = true
                if let a = account {
                    name = a.name
                    openingYuan = Money(a.openingBalanceCents).inputString
                    startDate = a.startDay.date()
                } else {
                    startDate = state.today.date()
                }
            }
        }.presentationDetents([.fraction(0.7), .large]).presentationDragIndicator(.visible).modifier(CleanSheetSurface()).modifier(FormExitGuard(isDirty: hasChanges, requested: $exitRequested))
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { error = "请输入账户名称"; return }
        let text = openingYuan.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty || text.range(of: #"^[+-]?[0-9]+(?:\.[0-9]{1,2})?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: text.isEmpty ? "0" : text, locale: Locale(identifier: "en_US_POSIX")),
              abs(decimal) <= Decimal(Money.maxProductCents) / 100 else {
            error = "请输入有效余额，最多两位小数；欠款可填负数。"; return
        }
        let openingCents = Money(yuan: decimal).cents
        let start = Day(from: startDate)
        let ok = state.perform("账户已保存") {
            if let a = account {
                try state.store.renameAccount(a.id, name: trimmed)
                try state.store.updateAccountOpening(a.id, openingCents: openingCents, startDay: start)
            } else {
                _ = try state.store.createAccount(ledgerID: ledgerID, name: trimmed, openingBalanceCents: openingCents, startDay: start)
            }
        }
        if ok { dismiss() } else { error = state.alertError }
    }

}

/// Category management uses the same library as entry selection.
struct CategoryManageView: View {
    @EnvironmentObject var state: AppState
    @State private var kind: TransactionKind = .expense
    var body: some View {
        if let ledger = state.activeLedger {
            CategoryLibraryContent(ledgerID: ledger.id, kind: kind, selected: .constant(nil), managementOnly: true)
                .safeAreaInset(edge: .top) {
                    Picker("收支类型", selection: $kind) {
                        Text("支出").tag(TransactionKind.expense)
                        Text("收入").tag(TransactionKind.income)
                    }.pickerStyle(.segmented).padding().background(.regularMaterial)
                }
                .navigationTitle("分类管理").navigationBarTitleDisplayMode(.inline)
        }
    }
}
