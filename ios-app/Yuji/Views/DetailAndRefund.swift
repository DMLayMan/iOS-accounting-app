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
    private func content(t: Transaction) -> some View {
        List {
            Section {
                VStack(spacing: 6) {
                    Text(titleText(t))
                        .font(.system(size: Design.captionSize)).foregroundColor(.secondary)
                    AmountText(text: "¥\(Money(t.amountCents).yuanDescription)",
                               size: 40, weight: .bold)
                        .padding(.vertical, 4)
                    if !t.isActive {
                        Text("已在回收站").foregroundColor(.red).font(.system(size: Design.captionSmall))
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
                    row("标签", t.tagIDs.compactMap { state.store.tag($0)?.name }.joined(separator: "、"))
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
                                    Text("退款 · \(r.date.month)/\(r.date.day)")
                                    Spacer()
                                    Text("¥\(Money(r.amountCents).yuanDescription)").foregroundColor(Design.sage)
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
                            Text("原支出 · \(orig.date.month)/\(orig.date.day)")
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
                    if t.kind != .refund {
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            } else {
                Section {
                    Button { state.restore(t.id) } label: { Label("恢复", systemImage: "arrow.uturn.right") }
                    Button(role: .destructive) { state.purge(t.id) } label: {
                        Label("永久删除", systemImage: "trash.fill")
                    }
                }
            }
        }
        .navigationTitle(titleText(t))
        .confirmationDialog("确认删除这条记录？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                state.delete(t)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(t.kind == .expense && state.store.totalRefunds(forExpense: t.id) > 0
                 ? "该支出已有退款，需先处理退款才能删除。"
                 : "删除后可在「我的 → 最近删除」恢复。")
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundColor(.secondary); Spacer(); Text(v).multilineTextAlignment(.trailing) }
    }
    private func titleText(_ t: Transaction) -> String {
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
    let original: Transaction
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var expression = ""
    @State private var date: Day
    @State private var accountID: EntityID?
    @State private var note = ""
    @State private var error: String?

    init(original: Transaction) {
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

    var body: some View {
        NavigationStack {
            Form {
                Section("原支出") {
                    HStack { Text("金额"); Spacer(); Text("¥\(Money(original.amountCents).yuanDescription)") }
                    HStack { Text("已退"); Spacer(); Text("¥\(Money(original.amountCents - remaining).yuanDescription)") }
                    HStack { Text("剩余可退"); Spacer(); Text("¥\(Money(remaining).yuanDescription)").foregroundColor(Design.sage) }
                }
                Section("此次退款") {
                    TextField("退款金额（可算式）", text: $expression)
                        .keyboardType(.numbersAndPunctuation)
                        .font(.system(size: 22, weight: .semibold))
                    if let r = result {
                        Text("将记录 ¥\(r.roundedDisplay)").foregroundColor(.secondary)
                    }
                    if let e = error { Text(e).foregroundColor(.red).font(.system(size: Design.captionSmall)) }
                    DatePicker("退款日期", selection: Binding(get: { date.date() },
                        set: { date = Day(from: $0) }), displayedComponents: .date)
                    Picker("退款到账账户", selection: Binding(get: { accountID ?? original.accountID },
                        set: { accountID = $0 })) {
                        ForEach(accounts) { Text($0.name).tag($0.id) }
                    }
                    TextField("说明（可选）", text: $note)
                }
            }
            .navigationTitle("退款")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.bold().disabled(cents == nil || cents! <= 0)
                }
            }
            .onAppear { accountID = original.accountID; expression = Money(remaining).yuanDescription }
        }
    }

    private func save() {
        guard let c = cents, c > 0 else { error = "请输入退款金额"; return }
        let acc = accountID ?? original.accountID
        if date < original.date { error = DomainError.refundDateBeforeOriginal.message; return }
        if c > remaining { error = "退款超出剩余可退额度"; return }
        let ok = state.addRefund(amountCents: c, date: date, accountID: acc, original: original.id,
                                 note: note, ledgerID: ledgerID)
        if ok { dismiss() }
    }
}
