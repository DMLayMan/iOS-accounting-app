import SwiftUI
import YujiCore

/// 分类选择（两级、单选叶子；一级可折叠；搜索）。
struct CategoryPickerView: View {
    let ledgerID: EntityID
    let kind: TransactionKind
    @Binding var selected: EntityID?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var state: AppState
    @State private var query = ""

    var body: some View {
        NavigationStack {
            let parents = state.store.categories(in: ledgerID, kind: kind, includeArchived: false)
                .filter { $0.parentID == nil }
            List {
                ForEach(parents) { parent in
                    Section {
                        ForEach(children(of: parent.id)) { leaf in
                            Button {
                                selected = leaf.id; dismiss()
                            } label: {
                                HStack {
                                    Text("\(parent.name) · \(leaf.name)").foregroundColor(.primary)
                                    Spacer()
                                    if selected == leaf.id {
                                        Image(systemName: "checkmark").foregroundColor(Design.sage)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(parent.name)
                    }
                }
            }
            .searchable(text: $query, prompt: "搜索分类")
            .navigationTitle(kind == .expense ? "选择支出分类" : "选择收入分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }

    private func children(of parentID: EntityID) -> [CategoryNode] {
        state.store.categories(in: ledgerID, kind: kind, includeArchived: false)
            .filter { $0.parentID == parentID }
            .filter { query.isEmpty || $0.name.contains(query) }
    }
}

/// 标签选择（两级、多选、搜索、显示完整路径）。
struct TagPickerView: View {
    let ledgerID: EntityID
    @Binding var selected: [EntityID]
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var state: AppState
    @State private var query = ""

    var body: some View {
        NavigationStack {
            let parents = state.store.tags(in: ledgerID, includeArchived: false)
                .filter { $0.parentID == nil }
            List {
                ForEach(parents) { parent in
                    Section(parent.name) {
                        ForEach(children(of: parent.id)) { leaf in
                            Button {
                                toggle(leaf.id)
                            } label: {
                                HStack {
                                    Text(leaf.name).foregroundColor(.primary)
                                    Spacer()
                                    if selected.contains(leaf.id) {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(Design.sage)
                                    } else {
                                        Image(systemName: "circle").foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "搜索标签")
            .navigationTitle("选择标签（可多选）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.bold() }
            }
        }
    }

    private func children(of parentID: EntityID) -> [TagNode] {
        state.store.tags(in: ledgerID, includeArchived: false)
            .filter { $0.parentID == parentID }
            .filter { query.isEmpty || $0.name.contains(query) }
    }
    private func toggle(_ id: EntityID) {
        if let i = selected.firstIndex(of: id) { selected.remove(at: i) }
        else { selected.append(id) }
    }
}

struct AccountPickerView: View {
    let accounts: [Account]
    @Binding var selected: EntityID?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(accounts) { acc in
                Button {
                    selected = acc.id; dismiss()
                } label: {
                    HStack {
                        Text(acc.name).foregroundColor(.primary)
                        Spacer()
                        if selected == acc.id { Image(systemName: "checkmark").foregroundColor(Design.sage) }
                    }
                }
            }
            .navigationTitle("选择账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

struct DatePickerSheet: View {
    @Binding var date: Day
    var onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pickerDate: Date = Date()
    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("发生日期", selection: $pickerDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                Spacer()
            }
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        date = Day(from: pickerDate); onChange(); dismiss()
                    }.bold()
                }
            }
            .onAppear { pickerDate = date.date() }
        }
    }
}
