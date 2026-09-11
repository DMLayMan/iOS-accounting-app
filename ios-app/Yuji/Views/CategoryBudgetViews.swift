import SwiftUI
import YujiCore

struct CategoryBudgetDraft: Identifiable, Equatable {
    var id = UUID()
    var period: BudgetPeriod = .month
    var categoryID: EntityID?
    var amount = ""
    func parsed() throws -> CategoryBudgetLimit {
        guard let categoryID else { throw DomainError.invalidParent("请选择支出分类") }
        guard let limit = try BudgetInput.parse(amount) else { throw DomainError.invalidAmount("请填写预算金额；填 0 表示计划零支出") }
        return CategoryBudgetLimit(period: period, categoryID: categoryID, limit: limit)
    }
}

struct CategoryBudgetRuleEditor: View {
    let ledgerID: EntityID
    let otherRules: [CategoryBudgetDraft]
    let initial: CategoryBudgetDraft
    var apply: (CategoryBudgetDraft) -> Void
    var remove: (() -> Void)?
    @State private var rule: CategoryBudgetDraft
    @State private var exitRequested = false
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editingAmount: Bool

    init(ledgerID: EntityID, draft: CategoryBudgetDraft, otherRules: [CategoryBudgetDraft], remove: (() -> Void)? = nil, apply: @escaping (CategoryBudgetDraft) -> Void) {
        self.ledgerID = ledgerID; self.initial = draft; self.otherRules = otherRules; self.apply = apply
        self.remove = remove
        _rule = State(initialValue: draft)
    }
    private var validation: String? {
        if rule.categoryID != nil && otherRules.contains(where: { $0.id != rule.id && $0.period == rule.period && $0.categoryID == rule.categoryID }) {
            return "这个分类已有同周期预算，请返回修改原规则"
        }
        if !rule.amount.isEmpty {
            do { _ = try BudgetInput.parse(rule.amount) } catch let e as DomainError { return e.message } catch { return "请检查金额" }
        }
        return nil
    }
    private var valid: Bool { validation == nil && (try? rule.parsed()) != nil }
    var body: some View {
        Form {
            Section {
                Picker("预算周期", selection: $rule.period) {
                    Text("每月").tag(BudgetPeriod.month); Text("每年").tag(BudgetPeriod.year)
                }.pickerStyle(.segmented).accessibilityIdentifier("categoryBudget.period")
                NavigationLink {
                    BudgetCategoryPicker(ledgerID: ledgerID, selected: $rule.categoryID)
                } label: {
                    Label(rule.categoryID.map { state.store.categoryPath($0) } ?? "选择分类", systemImage: "square.grid.2x2")
                }.accessibilityIdentifier("categoryBudget.choose")
            } footer: {
                Text("一级分类包含全部下级。一级、二级预算独立提醒，不相加；退款返还对应分类额度。")
            }
            Section {
                HStack {
                    TextField("预算金额（元）", text: $rule.amount).keyboardType(.decimalPad).focused($editingAmount)
                        .accessibilityLabel("分类预算金额，元").accessibilityIdentifier("categoryBudget.amount")
                    if !rule.amount.isEmpty {
                        Button { rule.amount = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(.secondary).frame(width: 44, height: 44) }
                            .buttonStyle(.plain).accessibilityLabel("清除金额").accessibilityIdentifier("categoryBudget.amount.clear")
                    }
                }
                if let validation { Text(validation).font(.caption).foregroundStyle(.red).accessibilityIdentifier("categoryBudget.error") }
            } header: { Text("预算金额（元）") } footer: {
                Text("完成后返回预算管理，点“保存预算”统一生效。")
            }
            if let remove {
                Section { Button("移除这条规则", role: .destructive) { remove(); dismiss() }.accessibilityIdentifier("categoryBudget.remove") }
            }
        }
        .navigationTitle(initial.categoryID == nil ? "添加分类预算" : "编辑分类预算").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { editingAmount = false; if rule != initial { exitRequested = true } else { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    guard valid else { return }
                    editingAmount = false; apply(rule); dismiss()
                }.disabled(!valid).accessibilityIdentifier("categoryBudget.apply")
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("收起键盘") { editingAmount = false } }
        }
        .modifier(FormExitGuard(isDirty: rule != initial, requested: $exitRequested))
    }
}

private struct BudgetCategoryPicker: View {
    let ledgerID: EntityID
    @Binding var selected: EntityID?
    @State private var query = ""
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    private var catalog: [CategoryNode] { state.store.categories(in: ledgerID, kind: .expense).filter { !$0.archived && state.store.category($0.parentID)?.archived != true } }
    private func matches(_ node: CategoryNode) -> Bool { query.isEmpty || state.store.categoryPath(node.id).localizedCaseInsensitiveContains(query) }
    var body: some View {
        List {
            Section {
                TextField("搜索分类", text: $query).submitLabel(.search).accessibilityIdentifier("categoryBudget.search")
            }
            ForEach(catalog.filter { parent in !parent.isLeaf && (matches(parent) || catalog.contains { $0.parentID == parent.id && matches($0) }) }) { parent in
                Section(parent.name) {
                    if matches(parent) { choice(parent, title: "全部" + parent.name) }
                    ForEach(catalog.filter { $0.parentID == parent.id && matches($0) }) { choice($0, title: $0.name) }
                }
            }
            if !catalog.contains(where: matches) { Text("没有匹配的分类").foregroundStyle(.secondary) }
        }
        .navigationTitle("预算分类").navigationBarTitleDisplayMode(.inline)
    }
    private func choice(_ node: CategoryNode, title: String) -> some View {
        Button { selected = node.id; dismiss() } label: {
            HStack {
                Label(title, systemImage: CategorySymbol.name(for: node))
                Spacer(minLength: 8)
                if selected == node.id { Image(systemName: "checkmark") }
            }.foregroundStyle(.primary).frame(minHeight: 44)
        }.accessibilityIdentifier("categoryBudget.select.\(node.id.raw)")
    }
}

/// Surfaces at most two overruns until the user explicitly expands the plan.
struct CategoryBudgetSummary: View {
    let rows: [CategoryBudgetSnapshot]
    let prefix: String
    var projected = false
    @State private var expanded = false
    private var exceeded: [CategoryBudgetSnapshot] { rows.filter { $0.overrun > 0 } }
    private var visible: [CategoryBudgetSnapshot] { expanded ? rows : Array(exceeded.prefix(2)) }
    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(projected ? "保存后的分类预算" : "分类预算").font(.caption.weight(.semibold))
                    Spacer(minLength: 8)
                    if rows.count > min(2, exceeded.count) || expanded {
                        Button(expanded ? "收起" : "全部 \(rows.count) 项") { expanded.toggle() }
                            .font(.caption).frame(minHeight: 44).accessibilityIdentifier(prefix + ".more")
                    }
                }
                if exceeded.isEmpty && !expanded {
                    Text("\(rows.count) 项预算均未超出").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier(prefix + ".within")
                }
                ForEach(visible) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(row.title) · \(row.period == .month ? "月" : "年")预算").font(.caption.weight(.medium))
                        Text(row.overrun > 0 ? "超出 \(statsMoney(row.overrun))" : "剩余 \(statsMoney(row.snapshot.remaining ?? 0))")
                            .font(.caption).monospacedDigit().foregroundStyle(row.overrun > 0 ? Color.red : Color.secondary)
                        if expanded, let limit = row.snapshot.limit {
                            Text("预算 \(statsMoney(limit)) · 已用 \(statsMoney(row.snapshot.spent))").font(.caption2).foregroundStyle(.secondary)
                        }
                    }.accessibilityElement(children: .combine).accessibilityIdentifier(prefix + ".row." + row.id)
                }
                if !expanded && exceeded.count > 2 {
                    Text("还有 \(exceeded.count - 2) 项超出预算").font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier(prefix + ".hidden")
                }
            }
        }
    }
}
