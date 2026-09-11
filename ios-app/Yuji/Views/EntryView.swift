import SwiftUI
import YujiCore

/// P04 记一笔 / 编辑。
/// 布局：取消/类型 → 大金额与常用分类 → 账户/日期一行、可选备注 → 数字区/保存固定底端。
/// 金额区直接输入算式；超两位小数需明确「按 ¥x.xx 保存」确认；失败/取消保留草稿。
struct EntryView: View {
    let ledger: Ledger
    let draft: Draft?
    var onDone: () -> Void
    var onSaved: () -> Void = {}
    var editing: YujiCore.Transaction? = nil

    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var kind: TransactionKind = .expense
    @State private var expression: String = ""
    @State private var date: Day
    @State private var accountID: EntityID?
    @State private var categoryID: EntityID?
    @State private var tagIDs: [EntityID] = []
    @State private var note: String = ""
    @State private var calcError: String?
    @State private var showCategoryPicker = false
    @State private var showAccountPicker = false
    @State private var showDatePicker = false
    @State private var showDiscardConfirm = false
    @State private var activeParentID: EntityID?
    @State private var categoryEditing = false
    @State private var categoryEditor: CategoryEditorContext?
    @State private var categoryPage = 0
    @State private var pageRequest = 0
    @State private var categoryError: String?
    @State private var orderUndo: (parentID: EntityID?, ids: [EntityID])?
    @State private var didLoad = false
    @State private var initialEntry: Draft?
    @FocusState private var noteFocused: Bool

    init(ledger: Ledger, draft: Draft?, onDone: @escaping () -> Void, editing: YujiCore.Transaction? = nil, onSaved: @escaping () -> Void = {}) {
        self.ledger = ledger; self.draft = draft; self.onDone = onDone; self.editing = editing; self.onSaved = onSaved
        _date = State(initialValue: editing?.date ?? draft?.date ?? Day(from: Date()))
    }

    private var parents: [CategoryNode] {
        state.store.categories(in: ledger.id, kind: kind, includeArchived: false).filter { !$0.isLeaf }
    }
    private var children: [CategoryNode] {
        guard let activeParentID else { return [] }
        return state.store.categories(in: ledger.id, kind: kind, includeArchived: false).filter { $0.parentID == activeParentID }
    }
    private var accounts: [Account] { state.store.accounts(in: ledger.id, includeArchived: false) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !showDiscardConfirm || !typeSize.isAccessibilitySize {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 20) {
                            kindButton("支出", .expense)
                            kindButton("收入", .income)
                        }.padding(.top, 8)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(displayAmount)
                                .font(typeSize.isAccessibilitySize ? .system(.largeTitle, design: .rounded).weight(.semibold) : .system(size: 46, weight: .semibold))
                                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                                .foregroundColor(calcError == nil ? Design.money(kind) : .red)
                                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                                .accessibilityIdentifier("entry.amount")
                            if let calcError { Text(calcError).font(.caption).foregroundColor(.red) }
                        }
                        .contentShape(Rectangle()).onTapGesture { noteFocused = false }
                        .accessibilityHint("轻点编辑金额")
                        EntryBudgetHint(ledgerID: ledger.id, date: date, kind: kind, cents: resolvedCents, replacingID: editing?.id, categoryID: categoryID)
                        HStack(spacing: 14) {
                            Button { noteFocused = false; showAccountPicker = true } label: {
                                Label(accountName, systemImage: "creditcard").lineLimit(1).fixedSize(horizontal: true, vertical: false).frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("entry.accountPicker")
                            Divider().frame(height: 12)
                            Button { noteFocused = false; showDatePicker = true } label: {
                                Label(shortDateText, systemImage: "calendar").lineLimit(1).fixedSize(horizontal: true, vertical: false).frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("entry.datePicker")
                        }.font(.system(size: 12)).foregroundColor(.secondary).frame(minHeight: 44)
                        categorySection
                        HStack(spacing: 8) {
                            Image(systemName: "text.alignleft").font(.system(size: 14)).foregroundColor(.secondary)
                            TextField("备注（可选）", text: $note)
                                .font(.body).focused($noteFocused).submitLabel(.done)
                                .onSubmit { noteFocused = false }
                                .accessibilityIdentifier("entry.note")
                            if noteFocused { Button("完成") { noteFocused = false }.font(.system(size: 13)) }
                        }.frame(minHeight: 42).overlay(alignment: .top) { Divider() }
                    }.padding(.horizontal, 20).padding(.bottom, 4)
                }
                .accessibilityIdentifier("entry.form")
                .disabled(showDiscardConfirm)
                }
                if showDiscardConfirm {
                    if typeSize.isAccessibilitySize {
                        ScrollView { exitDecision }
                    } else { exitDecision }
                } else if !noteFocused && !showCategoryPicker && !showAccountPicker && !showDatePicker && categoryEditor == nil {
                    if editing == nil && !typeSize.isAccessibilitySize {
                        Text("关闭自动保留草稿，保存后才记账").font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
                    }
                    keypad.accessibilityElement(children: .contain).accessibilityIdentifier("entry.amountKeypad")
                }
            }
            .background(Design.background(scheme).ignoresSafeArea())
            .tint(Design.primary(scheme))
            .navigationTitle(editing == nil ? "记一笔" : "编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(editing == nil ? "关闭" : "取消") { noteFocused = false; attemptClose() }
                        .accessibilityIdentifier("entry.close")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if editing == nil && (!expression.isEmpty || !note.isEmpty || draft != nil) {
                        Button { noteFocused = false; showDiscardConfirm = true } label: { Image(systemName: "trash") }
                            .accessibilityLabel("清空草稿").accessibilityIdentifier("entry.clearDraft")
                    }
                }
            }
            .onAppear(perform: loadDraftOrEditing)
            .onChange(of: categoryID) { id in
                if let parent = state.store.category(id)?.parentID { activeParentID = parent }
            }
            .onChange(of: state.store.data.categories) { _ in reconcileCategorySelection() }
            .interactiveDismissDisabled(hasChanges || showDiscardConfirm)
            .sheet(isPresented: $showCategoryPicker) {
                CategoryPickerView(ledgerID: ledger.id, kind: kind, selected: Binding(
                    get: { categoryID }, set: { categoryID = $0 }))
            }
            .sheet(item: $categoryEditor) { context in
                CategoryEditorView(ledgerID: ledger.id, kind: kind, context: context) { id in
                    orderUndo = nil
                    if let node = state.store.category(id), !node.archived {
                        activeParentID = node.parentID ?? node.id
                        if node.isLeaf && !categoryEditing { categoryID = id }
                    }
                    reconcileCategorySelection()
                }
            }
            .sheet(isPresented: $showAccountPicker) {
                AccountPickerView(accounts: accounts, selected: Binding(
                    get: { accountID }, set: { accountID = $0 }))
            }
            .sheet(isPresented: $showDatePicker) { DatePickerSheet(date: $date) {} }

        }
    }

    private func kindButton(_ title: String, _ value: TransactionKind) -> some View {
        Button {
            guard kind != value else { return }
            kind = value; categoryID = nil; activeParentID = parents.first?.id
            categoryEditing = false; orderUndo = nil
        } label: {
            Text(title).font(.system(size: 14, weight: kind == value ? .semibold : .regular))
                .foregroundColor(kind == value ? Design.money(value) : .secondary)
                .accessibilityAddTraits(kind == value ? [.isSelected] : [])
                .frame(minHeight: 44)
        }.accessibilityIdentifier("entry.kind.\(value.rawValue)")
    }

    private func reconcileCategorySelection() {
        if !parents.contains(where: { $0.id == activeParentID }) { activeParentID = parents.first?.id }
        if let id = categoryID,
           state.store.category(id)?.archived != false || state.store.category(state.store.category(id)?.parentID)?.archived != false {
            categoryID = nil
        }
    }

    // MARK: - 金额展示

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

    @ViewBuilder private var categorySection: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                Text("分类").font(.headline)
                Picker("一级分类", selection: $activeParentID) {
                    ForEach(parents) { Text($0.name).tag(EntityID?.some($0.id)) }
                }.pickerStyle(.menu)
                Button { noteFocused = false; showCategoryPicker = true } label: {
                    Label(categoryID.map { state.store.categoryPath($0) } ?? "选择二级分类", systemImage: "square.grid.2x2")
                        .font(.body).frame(minHeight: 44).fixedSize(horizontal: false, vertical: true)
                }.accessibilityIdentifier("entry.allCategories")
                Button {
                    noteFocused = false; categoryEditor = CategoryEditorContext(parentID: activeParentID)
                } label: { Label("新增二级分类", systemImage: "plus").font(.body).frame(minHeight: 44) }
                    .accessibilityIdentifier("entry.addCategory").disabled(activeParentID == nil)
            }.padding(.vertical, 8)
        } else { inlineCategorySection }
    }

    private var inlineCategorySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                Text(categoryEditing ? "编辑分类" : "分类").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                Spacer()
                Button(categoryEditing ? "完成" : "编辑") { noteFocused = false; categoryEditing.toggle() }
                    .frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("entry.editCategories")
                Button { noteFocused = false; showCategoryPicker = true } label: {
                    Label("全部分类", systemImage: "magnifyingglass").frame(minHeight: 44)
                }.accessibilityIdentifier("entry.allCategories")
            }.font(.system(size: 12)).foregroundColor(Design.primary(scheme)).frame(minHeight: 44)
            ZStack(alignment: .trailing) {
                InlineCategoryStrip(nodes: parents, parentStyle: true, selectedID: activeParentID, isEditing: categoryEditing,
                    hapticsEnabled: state.store.data.settings.hapticsEnabled, reduceMotion: state.store.data.settings.reduceMotion,
                    onSelect: { node in
                        noteFocused = false; activeParentID = node.id; categoryPage = 0
                        if categoryEditing { categoryEditor = CategoryEditorContext(node: node) }
                    }, onReorder: { reorder($0, parentID: nil) },
                    onDragBegan: { noteFocused = false; categoryEditing = true })
                if categoryEditing {
                    Button { noteFocused = false; categoryEditor = CategoryEditorContext(isGroup: true) } label: { Image(systemName: "plus") }
                        .frame(width: 44, height: 44).background(Design.background(scheme)).accessibilityLabel("新增一级分类")
                }
            }.frame(height: 44)
            HStack(alignment: .top, spacing: 8) {
                ZStack {
                    InlineCategoryStrip(nodes: children, tileHeight: 60, selectedID: categoryID, isEditing: categoryEditing, pageRequest: pageRequest,
                        hapticsEnabled: state.store.data.settings.hapticsEnabled, reduceMotion: state.store.data.settings.reduceMotion,
                        onSelect: { node in
                            noteFocused = false
                            if categoryEditing { categoryEditor = CategoryEditorContext(node: node) }
                            else { categoryID = node.id }
                        }, onReorder: { reorder($0, parentID: activeParentID) },
                        onDragBegan: { noteFocused = false; categoryEditing = true },
                        onPageChange: { page, _ in if categoryPage != page { categoryPage = page } })
                        .id(activeParentID)
                    if children.isEmpty { Text("点右侧新增分类").font(.system(size: 12)).foregroundColor(.secondary) }
                }
                VStack(spacing: 8) {
                    Button {
                        noteFocused = false
                        categoryEditor = CategoryEditorContext(parentID: activeParentID)
                    } label: {
                        VStack(spacing: 7) { Image(systemName: "plus").font(.system(size: 21)); Text("新增").font(.system(size: 11)) }
                            .frame(width: 44, height: 60)
                            .background(RoundedRectangle(cornerRadius: 13).fill(Design.lightFill(scheme)))
                    }.disabled(activeParentID == nil).accessibilityLabel("新增二级分类").accessibilityIdentifier("entry.addCategory")
                    if children.count > 8 {
                        Button { pageRequest += 1 } label: { Image(systemName: "chevron.right").font(.system(size: 13)).frame(width: 44, height: 44) }
                            .accessibilityLabel("下一页分类")
                    }
                }.foregroundColor(Design.primary(scheme))
            }.frame(height: children.count <= 4 ? 60 : 126)
            if let categoryError { Text(categoryError).font(.caption).foregroundColor(.red) }
            HStack(spacing: 8) {
                Text(categoryEditing ? "长按拖动排序 · 轻点编辑名称" : (categoryID == nil ? "请选择二级分类" : "已选 \(state.store.categoryPath(categoryID))"))
                    .font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    .accessibilityIdentifier("entry.selectedCategory")
                Spacer(minLength: 0)
                if orderUndo != nil {
                    Button("撤销排序") { undoOrder() }.font(.system(size: 11)).accessibilityIdentifier("entry.undoOrder")
                } else if children.count > 8 {
                    Text("\(categoryPage + 1) / \((children.count + 7) / 8)").font(.caption2).foregroundColor(.secondary)
                }
            }.frame(minHeight: 24)
        }
    }

    private func reorder(_ ids: [EntityID], parentID: EntityID?) -> Bool {
        let old = state.store.categories(in: ledger.id, kind: kind, includeArchived: false).filter { $0.parentID == parentID }.map(\.id)
        guard ids != old else { return true }
        let ok = state.perform { try state.store.reorderCategories(ledgerID: ledger.id, kind: kind, parentID: parentID, orderedIDs: ids) }
        categoryError = ok ? nil : state.alertError
        if ok { orderUndo = (parentID, old) }
        return ok
    }
    private func undoOrder() {
        guard let undo = orderUndo else { return }
        if state.perform(nil, { try state.store.reorderCategories(ledgerID: ledger.id, kind: kind, parentID: undo.parentID, orderedIDs: undo.ids) }) { orderUndo = nil }
    }

    private var accountName: String {
        if let id = accountID, let a = state.store.account(id) { return a.name }
        return accounts.first?.name ?? "选择账户"
    }
    private var dateText: String {
        String(format: "%04d 年 %02d 月 %02d 日", date.year, date.month, date.day)
    }
    private var shortDateText: String {
        date == state.today ? "今天" : (date.year == state.today.year ? String(format: "%d月%d日", date.month, date.day) : String(format: "%d年%d月%d日", date.year, date.month, date.day))
    }

    // MARK: - 数字键盘

    private var keypad: some View {
        VStack(spacing: 4) {
            if let r = evalResult, r.needsRoundingConfirmation, calcError == nil {
                Text("结果 \(r.exactDisplay)，将按 ¥\(r.roundedDisplay) 记账")
                    .font(.system(size: Design.captionSmall)).foregroundColor(Design.primary(scheme))
            }
            HStack(spacing: 6) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(["1","2","3","4","5","6","7","8","9",".","0","-"], id: \.self) { key in
                        Button { tapKey(key) } label: {
                            Text(key == "-" ? "−" : key).font(.system(size: 23)).frame(maxWidth: .infinity).frame(height: 46)
                                .background(RoundedRectangle(cornerRadius: 11).fill(Design.lightFill(scheme)))
                        }.buttonStyle(.plain).accessibilityIdentifier("entry.key.\(key)")
                    }
                }.frame(maxWidth: .infinity)
                VStack(spacing: 6) {
                    Button { tapKey("back") } label: { Image(systemName: "delete.left").frame(maxWidth: .infinity).frame(height: 46) }
                        .background(RoundedRectangle(cornerRadius: 11).fill(Design.lightFill(scheme)))
                        .accessibilityLabel("删除一位")
                    Menu {
                        Button("加 +") { tapKey("+") }; Button("减 −") { tapKey("-") }
                        Button("乘 ×") { tapKey("×") }; Button("除 ÷") { tapKey("÷") }
                        Button("左括号 (") { tapKey("(") }; Button("右括号 )") { tapKey(")") }
                        Button("清空金额", role: .destructive) { tapKey("clear") }
                    } label: { Text("+").font(.system(size: 23)).frame(maxWidth: .infinity).frame(height: 46) }
                    primaryAction: { tapKey("+") }
                    .background(RoundedRectangle(cornerRadius: 11).fill(Design.lightFill(scheme)))
                    .accessibilityLabel("加号，长按更多运算")
                    Button { save() } label: {
                        VStack(spacing: 8) { Image(systemName: "checkmark").font(.system(size: 22)); Text(saveButtonTitle).font(typeSize.isAccessibilitySize ? .body : .caption).minimumScaleFactor(0.6) }
                            .frame(maxWidth: .infinity).frame(height: 98)
                            .background(RoundedRectangle(cornerRadius: 11).fill(canSave ? Design.primary(scheme) : Color(.tertiarySystemFill)))
                            .foregroundColor(canSave ? (scheme == .dark ? .black : .white) : .secondary)
                    }.buttonStyle(.plain).disabled(!canSave).accessibilityIdentifier("entry.save")
                }.frame(width: 66)
            }.frame(maxWidth: .infinity)
        }.frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.vertical, 8).background(Design.surface(scheme))
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
            if ok { onDone() }
            return
        }
        if kind == .expense || kind == .income {
            guard let catID = categoryID else {
                state.alertError = DomainError.categoryRequired(kind == .expense ? "支出" : "收入").message; return
            }
            let ok = state.addExpense(expression: expression, date: date, accountID: accID,
                                      categoryID: catID, tagIDs: tagIDs, note: note,
                                      ledgerID: ledger.id, kind: kind, amountCents: cents)
            if ok { onSaved(); onDone() }
        }
    }

    private func loadDraftOrEditing() {
        guard !didLoad else { return }
        defer { didLoad = true }
        if let e = editing {
            kind = e.kind; expression = e.editingExpression
            accountID = e.accountID; categoryID = e.categoryID; tagIDs = e.tagIDs; note = e.note
        } else if let d = draft, d.ledgerID == ledger.id {
            kind = d.kind; expression = d.expression; date = d.date
            accountID = d.accountID; categoryID = d.categoryID; tagIDs = d.tagIDs; note = d.note
        } else if accountID == nil {
            date = state.today
            accountID = accounts.first?.id
        }
        recompute()
        activeParentID = state.store.category(categoryID)?.parentID ?? parents.first?.id
        reconcileCategorySelection()
        initialEntry = entrySnapshot
    }

    // Ignore timestamps when checking whether the user actually changed a field.
    private var entrySnapshot: Draft {
        Draft(ledgerID: ledger.id, kind: kind, expression: expression, date: date,
              accountID: accountID, categoryID: categoryID, tagIDs: tagIDs, note: note,
              updatedAt: Date(timeIntervalSince1970: 0))
    }
    private var hasChanges: Bool { didLoad && initialEntry != entrySnapshot }

    private var exitDecision: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editing == nil ? "清空这笔草稿？" : "放弃这次修改？").font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(editing == nil ? "清空后无法恢复。" : "原记录保持不变。")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("继续编辑") { showDiscardConfirm = false }
                .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                .background(Design.primary(scheme), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(scheme == .dark ? Color.black : Color.white).accessibilityIdentifier("entry.keepEditing")
            Button(editing == nil ? "清空草稿" : "放弃修改", role: .destructive) { discardAndClose() }
                .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("entry.discard")
        }.padding(20).background(Design.background(scheme))
            .overlay(alignment: .top) { Divider() }
            .accessibilityElement(children: .contain).accessibilityIdentifier("entry.exitDecision")
    }

    private func attemptClose() {
        if !hasChanges { onDone() }
        else if editing == nil { saveDraftAndClose() }
        else { showDiscardConfirm = true }
    }
    private func saveDraftAndClose() {
        var saved = entrySnapshot
        saved.updatedAt = Date()
        if state.saveDraft(saved, message: "草稿已保留，下次继续") { onDone() }
    }
    private func discardAndClose() {
        if editing != nil || state.clearDraft(ledgerID: ledger.id) { onDone() }
    }

}
