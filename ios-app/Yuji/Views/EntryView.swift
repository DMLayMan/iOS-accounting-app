import SwiftUI
import YujiCore

/// P04 记一笔 / 编辑。
/// 布局：取消/类型 → 大金额与常用分类 → 账户/日期一行、标签/备注一行 → 数字区/保存固定底端。
/// 金额区直接输入算式；超两位小数需明确「按 ¥x.xx 保存」确认；失败/取消保留草稿。
struct EntryView: View {
    let ledger: Ledger
    let draft: Draft?
    var onDone: () -> Void
    var editing: Transaction? = nil

    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var kind: TransactionKind = .expense
    @State private var expression: String = ""
    @State private var date: Day
    @State private var accountID: EntityID?
    @State private var categoryID: EntityID?
    @State private var tagIDs: [EntityID] = []
    @State private var note: String = ""
    @State private var calcError: String?
    @State private var requireRoundingConfirm = false
    @State private var showCategoryPicker = false
    @State private var showTagPicker = false
    @State private var showAccountPicker = false
    @State private var showDatePicker = false
    @State private var showDiscardConfirm = false
    @State private var isDirty = false

    init(ledger: Ledger, draft: Draft?, onDone: @escaping () -> Void, editing: Transaction? = nil) {
        self.ledger = ledger; self.draft = draft; self.onDone = onDone; self.editing = editing
        _date = State(initialValue: editing?.date ?? draft?.date ?? Day(from: Date()))
    }

    // 常用分类：支出前 7 个叶子 + 更多
    private var commonCategories: [CategoryNode] {
        let leaves = state.store.categories(in: ledger.id, kind: kind, includeArchived: false)
            .filter { $0.isLeaf }
        return Array(leaves.prefix(7))
    }

    private var accounts: [Account] { state.store.accounts(in: ledger.id, includeArchived: false) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // 类型切换
                        Picker("", selection: $kind) {
                            Text("支出").tag(TransactionKind.expense)
                            Text("收入").tag(TransactionKind.income)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                        .onChange(of: kind) { _ in
                            categoryID = nil  // 切换收支类型需重选分类
                            isDirty = true
                        }
                        .padding(.horizontal, 20).padding(.top, 16)

                        // 大金额
                        VStack(alignment: .leading, spacing: 4) {
                            Text(amountHeader).font(.system(size: Design.captionSize)).foregroundColor(.secondary)
                            Text(displayAmount)
                                .font(.system(size: Design.entryAmount, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(calcError == nil ? .primary : .red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                            if let err = calcError {
                                Label(err, systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: Design.captionSize)).foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal, 20)

                        // 常用分类 + 更多
                        categorySection

                        // 账户 / 日期 一行；标签 / 备注 一行
                        VStack(spacing: 0) {
                            compactRow(icon: "creditcard", title: accountName, chevron: true) {
                                showAccountPicker = true
                            }
                            Divider().padding(.leading, 44)
                            compactRow(icon: "calendar", title: dateText, chevron: true) {
                                showDatePicker = true
                            }
                            Divider().padding(.leading, 44)
                            compactRow(icon: "number", title: tagText, chevron: true) {
                                showTagPicker = true
                            }
                            Divider().padding(.leading, 44)
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.pencil").frame(width: 24).foregroundColor(.secondary)
                                TextField("备注（可选）", text: $note)
                                    .font(.system(size: Design.bodySize))
                                    .onChange(of: note) { _ in isDirty = true }
                            }
                            .padding(.vertical, 14)
                        }
                        .padding(.horizontal, 20)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                        .padding(.horizontal, 20)
                    }
                }

                // 数字区 / 保存 固定底端
                keypad
            }
            .background(Design.background(scheme).ignoresSafeArea())
            .navigationTitle(editing == nil ? "记一笔" : "编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { attemptClose() }
                }
            }
            .onAppear(perform: loadDraftOrEditing)
            .interactiveDismissDisabled(isDirty)  // 脏表单禁止下滑静默关闭，须走「取消」明确选择
            .sheet(isPresented: $showCategoryPicker) {
                CategoryPickerView(ledgerID: ledger.id, kind: kind, selected: $categoryID)
            }
            .sheet(isPresented: $showTagPicker) {
                TagPickerView(ledgerID: ledger.id, selected: $tagIDs)
            }
            .sheet(isPresented: $showAccountPicker) {
                AccountPickerView(accounts: accounts, selected: Binding(
                    get: { accountID }, set: { accountID = $0; isDirty = true }))
            }
            .sheet(isPresented: $showDatePicker) {
                DatePickerSheet(date: $date) { isDirty = true }
            }
            .confirmationDialog("有未保存的修改", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
                Button("保留草稿并退出") { saveDraftAndClose() }
                Button("放弃修改", role: .destructive) { discardAndClose() }
                Button("继续编辑", role: .cancel) {}
            } message: {
                Text("可以保留金额、分类和备注，下次从首页或 ＋ 继续。")
            }
        }
    }

    // MARK: - 金额展示

    private var amountHeader: String { kind == .expense ? "支出金额" : "收入金额" }

    private var displayAmount: String {
        if expression.isEmpty { return "¥0" }
        if let r = evalResult {
            return "¥" + r.roundedDisplay
        }
        return expression
    }

    private var evalResult: Calculator.Result? {
        guard !expression.isEmpty else { return nil }
        return try? Calculator.evaluate(expression)
    }

    private var resolvedCents: Int64? {
        guard let r = evalResult else { return nil }
        return r.roundedCents
    }

    // MARK: - 区块

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(commonCategories) { cat in
                        CategoryChip(node: cat, selected: categoryID == cat.id) {
                            categoryID = cat.id; isDirty = true; calcError = nil
                        }
                    }
                    Button { showCategoryPicker = true } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "ellipsis").font(.system(size: 18))
                            Text("更多").font(.system(size: Design.captionSmall))
                        }
                        .frame(width: 64, height: Design.categoryRowHeight - 8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Design.lightFill(scheme)))
                        .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func compactRow(icon: String, title: String, chevron: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24).foregroundColor(.secondary)
                Text(title).font(.system(size: Design.bodySize)).foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                if chevron { Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.secondary) }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var accountName: String {
        if let id = accountID, let a = state.store.account(id) { return a.name }
        return accounts.first?.name ?? "选择账户"
    }
    private var dateText: String {
        String(format: "%04d 年 %02d 月 %02d 日", date.year, date.month, date.day)
    }
    private var tagText: String {
        let names = tagIDs.compactMap { state.store.tag($0)?.name }
        return names.isEmpty ? "标签（可选）" : names.joined(separator: "、")
    }

    // MARK: - 数字键盘

    private let keys: [[String]] = [
        ["1", "2", "3", "+"],
        ["4", "5", "6", "-"],
        ["7", "8", "9", "×"],
        ["(", "0", ".", "÷"],
    ]

    private var keypad: some View {
        VStack(spacing: 8) {
            // 舍入确认提示
            if let r = evalResult, r.needsRoundingConfirmation, calcError == nil {
                Text("结果 \(r.exactDisplay)，将按 ¥\(r.roundedDisplay) 记账")
                    .font(.system(size: Design.captionSmall)).foregroundColor(Design.sage)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(keys, id: \.self) { row in
                    ForEach(row, id: \.self) { key in
                        Button { tapKey(key) } label: {
                            Text(key)
                                .font(.system(size: 22, weight: .medium))
                                .frame(height: Design.keyHeight)
                                .frame(maxWidth: .infinity)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Design.lightFill(scheme)))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button { tapKey(")") } label: {
                    Text(")").font(.system(size: 22, weight: .medium)).frame(height: Design.keyHeight)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Design.lightFill(scheme)))
                        .foregroundColor(.primary)
                }.buttonStyle(.plain)
                Button { tapKey("back") } label: {
                    Image(systemName: "delete.left").font(.system(size: 20)).frame(height: Design.keyHeight)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Design.lightFill(scheme)))
                        .foregroundColor(.primary)
                }.buttonStyle(.plain)
                Button { tapKey("clear") } label: {
                    Text("C").font(.system(size: 20, weight: .semibold)).frame(height: Design.keyHeight)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Design.lightFill(scheme)))
                        .foregroundColor(.red)
                }.buttonStyle(.plain)
                Button { save() } label: {
                    Text(saveButtonTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(height: Design.saveHeight)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10).fill(canSave ? Design.primary(scheme) : Design.primary(scheme).opacity(0.4)))
                        .foregroundColor(.white)
                }.buttonStyle(.plain).disabled(!canSave)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12).padding(.top, 6)
        .background(Design.surface(scheme))
    }

    private var saveButtonTitle: String {
        if let r = evalResult, r.needsRoundingConfirmation {
            return "按 ¥\(r.roundedDisplay) 保存"
        }
        return "保存"
    }

    private var canSave: Bool {
        guard let cents = resolvedCents else { return false }
        guard calcError == nil else { return false }
        if cents <= 0 { return false }                       // 拒绝负额/零额
        if !Money(cents).isWithinPositiveProductRange { return false }
        if (kind == .expense || kind == .income) && categoryID == nil { return false }
        if accountID == nil { return false }
        return true
    }

    private func tapKey(_ key: String) {
        isDirty = true
        switch key {
        case "back":
            if !expression.isEmpty { expression.removeLast() }
        case "clear":
            expression = ""
        default:
            expression.append(key)
        }
        recompute()
    }

    private func recompute() {
        guard !expression.isEmpty else { calcError = nil; return }
        do {
            _ = try Calculator.evaluate(expression)
            calcError = nil
        } catch let e as Calculator.Error {
            // 输入过程中的不完整不报错（如 "10+"），只对明确错误提示
            switch e {
            case .incompleteExpression, .empty, .unmatchedOpenParen:
                calcError = nil  // 允许继续输入
            default:
                calcError = e.message
            }
        } catch { calcError = "算式有误" }
    }

    // MARK: - 保存 / 草稿

    private func save() {
        guard let cents = resolvedCents, let accID = accountID else { return }
        guard calcError == nil else { return }
        if let e = editing {
            // 编辑：更新原记录（稳定 ID、修订号 +1），不新建重复交易。
            let ok = state.update(e.id, success: "已保存") { t in
                t.kind = kind
                t.amountCents = cents
                t.date = date
                t.accountID = accID
                t.categoryID = (kind == .expense || kind == .income) ? categoryID : nil
                t.tagIDs = tagIDs
                t.note = note
                t.expression = expression
            }
            if ok { state.clearDraft(ledgerID: ledger.id); onDone() }
            return
        }
        if kind == .expense || kind == .income {
            guard let catID = categoryID else {
                state.alertError = DomainError.categoryRequired(kind == .expense ? "支出" : "收入").message; return
            }
            let ok = state.addExpense(expression: expression, date: date, accountID: accID,
                                      categoryID: catID, tagIDs: tagIDs, note: note,
                                      ledgerID: ledger.id, kind: kind, amountCents: cents)
            if ok { onDone() }
        }
    }

    private func loadDraftOrEditing() {
        if let e = editing {
            kind = e.kind; expression = e.expression ?? Money(e.amountCents).yuanDescription
            accountID = e.accountID; categoryID = e.categoryID; tagIDs = e.tagIDs; note = e.note
            isDirty = false
        } else if let d = draft, d.ledgerID == ledger.id {
            kind = d.kind; expression = d.expression; date = d.date
            accountID = d.accountID; categoryID = d.categoryID; tagIDs = d.tagIDs; note = d.note
            isDirty = false
        } else if accountID == nil {
            accountID = accounts.first?.id
        }
        recompute()
    }

    private func attemptClose() {
        if isDirty { showDiscardConfirm = true } else { dismiss() }
    }
    private func saveDraftAndClose() {
        // 编辑模式不把改动存成新建草稿（否则会变成重复记账）；原记录未改动，可重新打开编辑。
        if editing == nil {
            state.saveDraft(Draft(ledgerID: ledger.id, kind: kind, expression: expression, date: date,
                                  accountID: accountID, categoryID: categoryID, tagIDs: tagIDs, note: note))
        }
        onDone()
    }
    private func discardAndClose() {
        state.clearDraft(ledgerID: ledger.id)
        onDone()
    }
}

struct CategoryChip: View {
    let node: CategoryNode
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "tag")
                    .font(.system(size: 16))
                Text(node.name).font(.system(size: Design.captionSmall)).lineLimit(1)
            }
            .frame(width: 64, height: Design.categoryRowHeight - 8)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(selected ? Design.selectedFill(scheme) : Design.lightFill(scheme)))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(selected ? Design.primary(scheme) : Color.clear, lineWidth: 1.5))
            .foregroundColor(selected ? Design.primary(scheme) : .primary)
        }
        .buttonStyle(.plain)
    }
}
