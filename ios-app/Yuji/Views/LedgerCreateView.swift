import SwiftUI
import YujiCore

/// Hosted either by a task sheet or the book switcher's navigation stack.
struct LedgerCreateView: View {
    var completion: (() -> Void)? = nil
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var monthly = ""
    @State private var yearly = ""
    @State private var keyboardVisible = false
    @State private var error: String?
    @State private var exitRequested = false
    @FocusState private var focused: Bool
    private var dirty: Bool { !name.isEmpty || !monthly.isEmpty || !yearly.isEmpty }

    var body: some View {
        Form {
            Section("账本名称") {
                TextField("例如：日常生活、旅行", text: $name)
                    .focused($focused).submitLabel(.done).onSubmit { focused = false }
                    .accessibilityIdentifier("ledger.newName")
            }
            BudgetFields(monthly: $monthly, yearly: $yearly)
            Section { Text("创建后直接使用，附带现金、银行卡和常用分类。预算从本月、本年起生效。") }
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("ledger.createError") }
        }
        .navigationTitle("新建账本").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { endEditing(); if !dirty { dismiss() } else { exitRequested = true } }
            }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { endEditing() } }
        }
        .safeAreaInset(edge: .bottom) {
            if !exitRequested && !keyboardVisible {
                Button("创建并使用") {
                    endEditing()
                    do {
                        let month = try BudgetInput.parse(monthly); let year = try BudgetInput.parse(yearly)
                        if state.createAndSwitchLedger(name: name, monthlyBudget: month, yearlyBudget: year) {
                            if let completion { completion() } else { dismiss() }
                        } else { error = state.alertError }
                    } catch let e as DomainError { error = e.message } catch { self.error = "请检查预算金额" }
                }.buttonStyle(SolidActionStyle()).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || BudgetFields.validation(monthly, yearly) != nil)
                    .accessibilityIdentifier("ledger.saveNew")
                    .padding(20).background(Color(.systemBackground))
            }
        }
        .modifier(FormExitGuard(isDirty: dirty, requested: $exitRequested))
        .modifier(CleanSheetSurface())
        .presentationDetents([.fraction(0.7), .large]).presentationDragIndicator(.visible)
        .modifier(BudgetKeyboardVisibility(visible: $keyboardVisible))
    }
    private func endEditing() {
        focused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
