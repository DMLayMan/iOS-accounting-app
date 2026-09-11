import SwiftUI
import YujiCore

/// Keep the next field reachable on small sheets while the system keyboard is open.
struct BudgetKeyboardVisibility: ViewModifier {
    @Binding var visible: Bool
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in visible = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in visible = false }
    }
}

struct BudgetFields: View {
    @Binding var monthly: String
    @Binding var yearly: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Section {
            field("每月预算", value: $monthly, id: "budget.monthly")
            field("每年预算", value: $yearly, id: "budget.yearly")
            if let message = Self.validation(monthly, yearly) {
                Text(message).font(.caption).foregroundStyle(.red).accessibilityIdentifier("budget.inputError")
            }
        } header: { Text("预算（可选）") } footer: {
            Text("留空不设预算；填 0 表示计划零支出。月、年额度独立，按周期重置，不滚存。")
        }
    }
    private func field(_ title: String, value: Binding<String>, id: String) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            HStack(spacing: 8) {
                Text(title).fixedSize()
                if typeSize.isAccessibilitySize { Text("元").font(.caption).foregroundStyle(.secondary) }
            }
            HStack(spacing: 4) {
                TextField("未设置", text: value).keyboardType(.decimalPad)
                    .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                    .accessibilityLabel(title + "，元").accessibilityIdentifier(id)
                if !typeSize.isAccessibilitySize { Text("元").foregroundStyle(.secondary) }
                if !value.wrappedValue.isEmpty {
                    Button { value.wrappedValue = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(.secondary).frame(width: 44, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel("清除" + title).accessibilityIdentifier(id + ".clear")
                }
            }
        }
    }
    static func validation(_ monthly: String, _ yearly: String) -> String? {
        do { _ = try BudgetInput.parse(monthly); _ = try BudgetInput.parse(yearly); return nil }
        catch let error as DomainError { return error.message }
        catch { return "请检查预算金额" }
    }
}

struct LedgerBudgetEditor: View {
    let ledgerID: EntityID
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var monthly = ""
    @State private var yearly = ""
    @State private var initialMonthly = ""
    @State private var initialYearly = ""
    @State private var loaded = false
    @State private var error: String?
    @State private var exitRequested = false
    @State private var keyboardVisible = false
    @State private var categoryRules: [CategoryBudgetDraft] = []
    @State private var initialCategoryRules: [CategoryBudgetDraft] = []
    @State private var editingRule: CategoryBudgetDraft?
    private var dirty: Bool { monthly != initialMonthly || yearly != initialYearly || categoryRules != initialCategoryRules }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(state.store.ledger(ledgerID)?.name ?? "账本").font(.headline) }
                BudgetFields(monthly: $monthly, yearly: $yearly)
                Section {
                    ForEach(categoryRules) { rule in
                        Button { editingRule = rule } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(state.store.categoryPath(rule.categoryID)).foregroundStyle(.primary)
                                Text("\(rule.period == .month ? "每月" : "每年") · \(rule.amount) 元").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.accessibilityIdentifier("budget.category.edit.\(rule.period.rawValue).\(rule.categoryID?.raw ?? "")")
                            .swipeActions { Button("移除", role: .destructive) { categoryRules.removeAll { $0.id == rule.id } } }
                    }
                    Button { editingRule = CategoryBudgetDraft() } label: { Label("添加分类预算", systemImage: "plus") }
                        .accessibilityIdentifier("budget.category.add")
                } header: { Text("分类预算 · \(categoryRules.count) 项") } footer: {
                    Text("可选一级或二级支出分类，不限制规则条数。修改后点“保存预算”统一生效。")
                }
                Section {
                    Text("月预算从 \(String(state.today.year)) 年 \(state.today.month) 月起生效，年预算从 \(String(state.today.year)) 年起生效。以后沿用，历史周期保持原额度。")
                    Text("净支出占用预算，退款返还额度；收入与转账不占用。超预算仍可保存记账。")
                }.font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("budget.saveError") }
            }
            .navigationTitle("账本预算").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { endEditing(); if dirty { exitRequested = true } else { dismiss() } } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { endEditing() } }
            }
            .safeAreaInset(edge: .bottom) {
                if !exitRequested && !keyboardVisible && editingRule == nil {
                    Button("保存预算", action: save).buttonStyle(SolidActionStyle())
                        .disabled(!loaded || BudgetFields.validation(monthly, yearly) != nil || state.store.ledger(ledgerID)?.archived != false)
                        .accessibilityIdentifier("budget.save").padding(20).background(Color(.systemBackground))
                }
            }
            .modifier(FormExitGuard(isDirty: dirty, requested: $exitRequested))
            .navigationDestination(isPresented: Binding(get: { editingRule != nil }, set: { if !$0 { editingRule = nil } })) {
                if let rule = editingRule {
                    CategoryBudgetRuleEditor(ledgerID: ledgerID, draft: rule, otherRules: categoryRules,
                        remove: categoryRules.contains(where: { $0.id == rule.id }) ? { categoryRules.removeAll { $0.id == rule.id } } : nil) { updated in
                        if let index = categoryRules.firstIndex(where: { $0.id == updated.id }) { categoryRules[index] = updated }
                        else { categoryRules.append(updated) }
                    }
                }
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.fraction(0.7), .large])
        .presentationDragIndicator(.visible).modifier(CleanSheetSurface())
        .modifier(BudgetKeyboardVisibility(visible: $keyboardVisible))
        .onAppear {
            guard !loaded else { return }
            monthly = state.store.budgetLimit(in: ledgerID, period: .month, containing: state.today).map { Money($0).inputString } ?? ""
            yearly = state.store.budgetLimit(in: ledgerID, period: .year, containing: state.today).map { Money($0).inputString } ?? ""
            initialMonthly = monthly; initialYearly = yearly; loaded = true
            categoryRules = state.store.categoryBudgetLimits(in: ledgerID, containing: state.today).sorted {
                if $0.period != $1.period { return $0.period == .month }
                return state.store.categoryPath($0.categoryID) < state.store.categoryPath($1.categoryID)
            }.map {
                CategoryBudgetDraft(period: $0.period, categoryID: $0.categoryID, amount: Money($0.limit).inputString)
            }
            initialCategoryRules = categoryRules
        }
    }
    private func save() {
        endEditing()
        do {
            let month = try BudgetInput.parse(monthly); let year = try BudgetInput.parse(yearly)
            let limits = try categoryRules.map { try $0.parsed() }
            if state.perform("预算已更新", {
                try state.store.setBudgets(ledgerID: ledgerID, monthly: month, yearly: year, effective: state.today)
                try state.store.setCategoryBudgets(ledgerID: ledgerID, limits: limits, effective: state.today)
            }) { dismiss() }
            else { error = state.alertError }
        } catch let e as DomainError { error = e.message } catch { self.error = "请检查预算金额" }
    }
    private func endEditing() { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
}

struct StatsBudgetView: View {
    let ledgerID: EntityID
    let period: BudgetPeriod
    let day: Day
    let cutoff: Day
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var showEditor = false
    var body: some View {
        let snapshot = state.store.budget(in: ledgerID, period: period, containing: day, through: cutoff)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(period == .month ? "\(String(day.year)) 年 \(day.month) 月预算" : "\(String(day.year)) 年预算").font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if state.activeLedger?.archived == false {
                    Button("管理") { showEditor = true }.font(.subheadline).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("stats.budgetManage")
                }
            }
            if let remaining = snapshot.remaining, let limit = snapshot.limit {
                Text(remaining >= 0 ? "剩余 \(statsMoney(remaining))" : "超出 \(statsMoney(-remaining))")
                    .font(.headline).monospacedDigit().foregroundStyle(remaining < 0 ? Color.red : .primary)
                    .accessibilityIdentifier("stats.budgetRemaining")
                ProgressView(value: snapshot.progress).tint(remaining < 0 ? .red : Design.primary(scheme))
                    .accessibilityLabel("预算使用进度").accessibilityValue("净支出 \(statsMoney(snapshot.spent))，预算 \(statsMoney(limit))")
                Text("预算 \(statsMoney(limit)) · 已用 \(statsMoney(snapshot.spent))")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("stats.budgetAmounts")
                Text("账本总预算 · 按净支出计算").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("未设置账本总预算").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("stats.budgetUnset")
            }
            CategoryBudgetSummary(rows: state.store.categoryBudgets(in: ledgerID, period: period, containing: day, through: cutoff), prefix: "stats.categoryBudget")
                .id("\(ledgerID.raw)-\(period)-\(day)")
        }.padding(.vertical, 4)
        .sheet(isPresented: $showEditor) { LedgerBudgetEditor(ledgerID: ledgerID) }
    }
}

struct EntryBudgetHint: View {
    let ledgerID: EntityID
    let date: Day
    let kind: TransactionKind
    let cents: Int64?
    let replacingID: EntityID?
    let categoryID: EntityID?
    @EnvironmentObject private var state: AppState
    var body: some View {
        let preview = cents.flatMap { Money($0).isWithinPositiveProductRange ? BudgetEntryPreview(kind: kind, cents: $0, date: date, replacingID: replacingID, categoryID: categoryID) : nil }
        let cutoff = max(state.today, date)
        let month = state.store.budget(in: ledgerID, period: .month, containing: date, through: cutoff, preview: preview)
        let year = state.store.budget(in: ledgerID, period: .year, containing: date, through: cutoff, preview: preview)
        if month.limit != nil || year.limit != nil {
            VStack(alignment: .leading, spacing: 3) {
                if kind == .income && replacingID == nil {
                    Text("收入不占用预算").font(.caption).foregroundStyle(.secondary)
                } else {
                    if let left = month.remaining { line("\(date.month) 月", remaining: left, projected: preview != nil) }
                    if let left = year.remaining { line("\(String(date.year)) 年", remaining: left, projected: preview != nil) }
                }
            }.accessibilityElement(children: .combine).accessibilityIdentifier("entry.budgetHint")
        }
        if let categoryID, kind == .expense {
            CategoryBudgetSummary(rows: state.store.categoryBudgets(in: ledgerID, containing: date, through: cutoff, preview: preview, matching: categoryID),
                                  prefix: "entry.categoryBudget", projected: preview != nil)
                .id("\(ledgerID.raw)-\(categoryID.raw)-\(date)")
        }
    }
    private func line(_ period: String, remaining: Int64, projected: Bool) -> some View {
        Text("\(projected ? "保存后 · " : "")\(period)预算\(remaining < 0 ? "超出" : "剩余") \(statsMoney(abs(remaining)))")
            .font(.caption).foregroundStyle(remaining < 0 ? Color.red : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
