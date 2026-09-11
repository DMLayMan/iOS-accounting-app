import SwiftUI
import YujiCore

/// P03 流水详情：完整字段、分类路径、标签、账户、退款关系、操作入口。
struct TransactionDetailView: View {
    let transactionID: EntityID
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var showRefund = false
    @State private var showDeleteConfirm = false
    @State private var showPurgeConfirm = false

    var body: some View {
        Group {
            if let t = state.store.transaction(transactionID) {
                content(t: t)
            } else {
                Text("记录不存在").onAppear { dismiss() }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEdit) {
            if let t = state.store.transaction(transactionID), let ledger = state.store.ledger(t.ledgerID) {
                EntryView(ledger: ledger, draft: nil, onDone: { showEdit = false }, editing: t)
            }
        }
        .sheet(isPresented: $showRefund) {
            if let t = state.store.transaction(transactionID) {
                RefundView(original: t)
            }
        }
    }

    @ViewBuilder
    private func content(t: YujiCore.Transaction) -> some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text(titleText(t) == t.kind.displayName ? titleText(t) : "\(t.kind.displayName) · \(titleText(t))")
                        .font(.subheadline).foregroundColor(.secondary)
                    AmountText(text: "\(t.kind == .expense ? "−" : t.kind == .transfer ? "" : "+")¥\(Money(t.amountCents).yuanDescription)",
                               size: 40, weight: .bold, color: Design.money(t.kind))
                        .accessibilityIdentifier("detail.amount")
                        .padding(.vertical, 4)
                    if !t.isActive {
                        Text("已在回收站").foregroundColor(.red).font(.caption)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("详情") {
                row("日期", String(format: "%04d-%02d-%02d", t.date.year, t.date.month, t.date.day))
                row("账户", state.store.account(t.accountID)?.name ?? "—")
                if t.kind == .transfer, let to = t.transferToAccountID {
                    row("转入账户", state.store.account(to)?.name ?? "—")
                }
                if (t.kind == .expense || t.kind == .income), let cid = t.categoryID {
                    row("分类", categoryPath(cid))
                }
                if !t.tagIDs.isEmpty {
                    row("历史附加信息", t.tagIDs.compactMap { state.store.tag($0)?.name }.joined(separator: "、"))
                }
                if !t.note.isEmpty { row("备注", t.note) }
                if let expr = t.expression, !expr.isEmpty { row("计算式", expr) }
            }

            // 退款关系
            if t.kind == .expense {
                Section("退款") {
                    let refunded = state.store.totalRefunds(forExpense: t.id)
                    row("原金额", "¥\(Money(t.amountCents).yuanDescription)")
                    row("已退款", "¥\(Money(refunded).yuanDescription)")
                    row("剩余可退", "¥\(Money(max(0, t.amountCents - refunded)).yuanDescription)")
                    if refunded < t.amountCents && t.isActive {
                        Button { showRefund = true } label: {
                            Label("记一笔退款", systemImage: "arrow.uturn.backward")
                        }
                    }
                    let refunds = state.store.data.transactions.filter {
                        $0.isActive && $0.kind == .refund && $0.originalExpenseID == t.id
                    }
                    if !refunds.isEmpty {
                        ForEach(refunds) { r in
                            NavigationLink {
                                TransactionDetailView(transactionID: r.id)
                            } label: {
                                HStack {
                                    Text("退款 · \(statsDayText(r.date))")
                                    Spacer()
                                    Text("¥\(Money(r.amountCents).yuanDescription)").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            if t.kind == .refund, let origID = t.originalExpenseID, let orig = state.store.transaction(origID) {
                Section("原支出") {
                    NavigationLink {
                        TransactionDetailView(transactionID: origID)
                    } label: {
                        HStack {
                            Text("原支出 · \(statsDayText(orig.date))")
                            Spacer()
                            Text("¥\(Money(orig.amountCents).yuanDescription)").foregroundColor(.secondary)
                        }
                    }
                }
            }

            if t.isActive {
                Section {
                    if t.kind == .expense || t.kind == .income {
                        Button { showEdit = true } label: { Label("编辑", systemImage: "pencil") }
                    }
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            } else {
                Section {
                    Button { state.restore(t.id) } label: { Label("恢复", systemImage: "arrow.uturn.right") }
                    Button(role: .destructive) { showPurgeConfirm = true } label: {
                        Label("永久删除", systemImage: "trash.fill")
                    }
                }
            }
        }
        .navigationTitle(titleText(t))
        .alert("永久删除这条记录？", isPresented: $showPurgeConfirm) {
            Button("永久删除", role: .destructive) {
                state.purge(t.id)
                if state.store.transaction(t.id) == nil { dismiss() }
            }
            Button("取消", role: .cancel) {}
        } message: { Text("永久删除后无法恢复。") }
        .alert("删除这条记录？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                state.delete(t)
                if state.store.transaction(t.id)?.isActive == false { dismiss() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(t.kind == .expense && state.store.totalRefunds(forExpense: t.id) > 0
                 ? "该支出已有退款，需先处理退款才能删除。"
                 : "删除后可在「我的 → 最近删除」恢复。")
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).multilineTextAlignment(.trailing) }
            VStack(alignment: .leading, spacing: 8) { Text(k).foregroundStyle(.secondary); Text(v) }
        }.padding(.vertical, 2)
    }
    private func titleText(_ t: YujiCore.Transaction) -> String {
        switch t.kind {
        case .expense: return state.store.category(t.categoryID)?.name ?? "支出"
        case .income: return state.store.category(t.categoryID)?.name ?? "收入"
        case .refund: return "退款"
        case .transfer: return "转账"
        }
    }
    private func categoryPath(_ id: EntityID) -> String {
        guard let c = state.store.category(id) else { return "—" }
        if let pid = c.parentID, let p = state.store.category(pid) { return "\(p.name) / \(c.name)" }
        return c.name
    }
}

/// P05 退款：原消费概要、已退/可退、此次金额、退款账户与日期。
struct RefundView: View {
    let original: YujiCore.Transaction
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var expression = ""
    @State private var date: Day
    @State private var accountID: EntityID?
    @State private var note = ""
    @State private var exitRequested = false
    @State private var error: String?
    @FocusState private var focused: Bool

    init(original: YujiCore.Transaction) {
        self.original = original
        _date = State(initialValue: Day(from: Date()))
    }

    private var remaining: Int64 {
        max(0, original.amountCents - state.store.totalRefunds(forExpense: original.id))
    }
    private var result: Calculator.Result? { try? Calculator.evaluate(expression) }
    private var cents: Int64? { result?.roundedCents }
    private var ledgerID: EntityID { original.ledgerID }
    private var accounts: [Account] { state.store.accounts(in: ledgerID, includeArchived: false) }

    private var hasChanges: Bool {
        accountID != nil && (expression != Money(remaining).inputString || !note.isEmpty || accountID != original.accountID || date != state.today)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("原支出") {
                    HStack { Text("金额"); Spacer(); Text("¥\(Money(original.amountCents).yuanDescription)") }
                    HStack { Text("已退"); Spacer(); Text("¥\(Money(original.amountCents - remaining).yuanDescription)") }
                    HStack { Text("剩余可退"); Spacer(); Text("¥\(Money(remaining).yuanDescription)").foregroundStyle(.tint) }
                }
                Section("此次退款") {
                    TextField("退款金额（可算式）", text: $expression).focused($focused)
                        .keyboardType(.numbersAndPunctuation).accessibilityIdentifier("refund.amount")
                        .font(.system(size: 22, weight: .semibold))
                    if let r = result {
                        Text("将记录 ¥\(r.roundedDisplay)").foregroundColor(.secondary)
                    }
                    if let cents, cents > remaining {
                        Text("超过剩余可退金额 ¥\(Money(remaining).yuanDescription)")
                            .font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("refund.limitError")
                    }
                    if let e = error { Text(e).foregroundColor(.red).font(.caption) }
                    DatePicker("退款日期", selection: Binding(get: { date.date() },
                        set: { date = Day(from: $0) }), displayedComponents: .date)
                    Picker("退款到账账户", selection: Binding(get: { accountID ?? original.accountID },
                        set: { accountID = $0 })) {
                        ForEach(accounts) { Text($0.name).tag($0.id) }
                    }
                    TextField("说明（可选）", text: $note).focused($focused)
                }
            }
            .navigationTitle("退款")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { focused = false; if hasChanges { exitRequested = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(result?.saveActionTitle ?? "保存") { save() }.bold().disabled(cents == nil || cents! <= 0 || cents! > remaining).accessibilityIdentifier("refund.save")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { if accountID == nil { date = state.today; accountID = original.accountID; expression = Money(remaining).inputString } }
        }.presentationDetents([.fraction(0.7), .large]).presentationDragIndicator(.visible).modifier(CleanSheetSurface()).modifier(FormExitGuard(isDirty: hasChanges, requested: $exitRequested))
    }

    private func save() {
        guard let c = cents, c > 0 else { error = "请输入退款金额"; return }
        let acc = accountID ?? original.accountID
        if date < original.date { error = DomainError.refundDateBeforeOriginal.message; return }
        if c > remaining { error = "退款超出剩余可退额度"; return }
        let ok = state.addRefund(amountCents: c, date: date, accountID: acc, original: original.id,
                                 note: note, ledgerID: ledgerID)
        if ok { dismiss() } else { error = state.alertError }
    }
}
