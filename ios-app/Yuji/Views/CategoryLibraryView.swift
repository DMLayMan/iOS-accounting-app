import SwiftUI
import YujiCore

struct CategoryPickerView: View {
    let ledgerID: EntityID
    let kind: TransactionKind
    @Binding var selected: EntityID?
    var body: some View {
        NavigationStack {
            CategoryLibraryContent(ledgerID: ledgerID, kind: kind, selected: $selected)
                .navigationTitle("选择分类").navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct CategoryLibraryContent: View {
    let ledgerID: EntityID
    let kind: TransactionKind
    @Binding var selected: EntityID?
    var managementOnly = false
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var query = ""
    @State private var managing = false
    @State private var showArchived = false
    @State private var editor: CategoryEditorContext?
    @State private var deletion: CategoryNode?
    @State private var archiveTarget: CategoryNode?
    @State private var error: String?
    @FocusState private var searching: Bool

    private var isManaging: Bool { managementOnly || managing }
    private var catalog: [CategoryNode] { state.store.categories(in: ledgerID, kind: kind) }
    private var text: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var parents: [CategoryNode] {
        catalog.filter { !$0.isLeaf && (isManaging && showArchived || !$0.archived) }
            .filter { text.isEmpty || $0.name.localizedCaseInsensitiveContains(text) || !children($0).isEmpty }
    }
    private func children(_ parent: CategoryNode) -> [CategoryNode] {
        catalog.filter { $0.parentID == parent.id && (isManaging && showArchived || !$0.archived && !parent.archived) }
            .filter { text.isEmpty || $0.name.localizedCaseInsensitiveContains(text) || parent.name.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("搜索一级或二级分类", text: $query).focused($searching)
                        .submitLabel(.done).onSubmit { searching = false }
                        .accessibilityIdentifier("categories.search")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .accessibilityLabel("清空搜索").frame(minWidth: 44, minHeight: 44)
                    }
                }
                if isManaging { Toggle("显示已归档", isOn: $showArchived) }
                if let error { Text(error).font(.footnote).foregroundColor(.red) }
            } footer: {
                Text(isManaging ? "在记账页长按分类可调整顺序。归档保留历史。" : "直接选择一个二级分类，即可返回记账。")
            }
            ForEach(parents) { parent in
                Section {
                    if isManaging {
                        ForEach(children(parent)) { leaf in row(leaf) }
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 1 : 3), spacing: 8) {
                            ForEach(children(parent)) { leaf in
                                Button { searching = false; selected = leaf.id; dismiss() } label: {
                                    Label(leaf.name, systemImage: CategorySymbol.name(for: leaf)).font(.subheadline).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(selected == leaf.id ? Design.selectedFill(scheme) : Design.lightFill(scheme)))
                                }.buttonStyle(.plain)
                            }
                        }.listRowSeparator(.hidden)
                    }
                    if isManaging {
                        Button {
                            openEditor(CategoryEditorContext(parentID: parent.id, name: text))
                        } label: { Label("新增二级分类", systemImage: "plus") }
                        .disabled(parent.archived)
                    } else if children(parent).isEmpty {
                        Text("暂无二级分类").foregroundColor(.secondary)
                    }
                } header: {
                    HStack {
                        Text(parent.name + (parent.archived ? " · 已归档" : ""))
                        Spacer()
                        if isManaging { actions(parent) }
                    }
                }
            }
            if parents.isEmpty { Text("没有匹配的分类").foregroundColor(.secondary) }
            Section {
                Button {
                    openEditor(CategoryEditorContext(name: text))
                } label: { Label("新建二级分类", systemImage: "plus.circle") }
                if isManaging {
                    Button {
                        openEditor(CategoryEditorContext(name: text, isGroup: true))
                    } label: { Label("新建一级分组", systemImage: "folder.badge.plus") }
                }
            }
        }
        .tint(Design.primary(scheme))
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            if !managementOnly {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button(managing ? "返回选择" : "管理") { searching = false; managing.toggle() }
                }
            }
        }
        .sheet(item: $editor) { context in
            CategoryEditorView(ledgerID: ledgerID, kind: kind, context: context) { id in
                if !isManaging, let node = state.store.category(id), node.isLeaf, !node.archived { selected = id; dismiss() }
            }
        }
        .confirmationDialog("删除分类？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
            Button("删除未使用分类", role: .destructive) {
                if let node = deletion { mutate { try state.store.deleteCategory(node.id) } }
                deletion = nil
            }
        } message: {
            Text("此分类及下级没有交易、草稿或预算引用。删除后无法恢复；也可以选择归档。")
        }
        .confirmationDialog("归档分类？", isPresented: Binding(get: { archiveTarget != nil }, set: { if !$0 { archiveTarget = nil } }), titleVisibility: .visible) {
            Button("归档，保留历史") {
                if let node = archiveTarget {
                    if mutate({ try state.store.archiveCategory(node.id, archived: true) }),
                       selected == node.id || state.store.category(selected)?.parentID == node.id { selected = nil }
                }
                archiveTarget = nil
            }
        } message: {
            Text("归档后不再用于新记录，已有账单仍保留。一级分组会连同全部下级归档，并取消置顶。")
        }
    }

    private func row(_ node: CategoryNode) -> some View {
        HStack {
            Button {
                searching = false
                if isManaging { openEditor(CategoryEditorContext(node: node)) }
                else { selected = node.id; dismiss() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: CategorySymbol.name(for: node))
                        .foregroundColor(Design.primary(scheme))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(node.name).foregroundColor(node.archived ? .secondary : .primary)
                        if isManaging {
                            Text(node.archived ? "已归档" : "\(state.store.categoryReferenceCount(node.id)) 处引用（含预算）")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if isManaging { actions(node) }
        }
    }

    private func actions(_ node: CategoryNode) -> some View {
        Menu {
            Button("编辑分类") { openEditor(CategoryEditorContext(node: node)) }
            if node.archived {
                Button(node.isLeaf ? "恢复使用" : "恢复分组及下级") {
                    mutate { try state.store.archiveCategory(node.id, archived: false) }
                }
            } else {
                Button("归档") { searching = false; archiveTarget = node }
            }
            if state.store.categoryReferenceCount(node.id) == 0 && selected != node.id && state.store.category(selected)?.parentID != node.id {
                Button("删除未使用分类", role: .destructive) { searching = false; deletion = node }
            }
        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
        .accessibilityLabel("管理 \(node.name)")
    }

    private func openEditor(_ context: CategoryEditorContext) { searching = false; editor = context }
    @discardableResult private func mutate(_ action: () throws -> Void) -> Bool {
        let ok = state.perform(nil, action); error = ok ? nil : state.alertError; return ok
    }
}

struct CategoryEditorContext: Identifiable {
    let id = UUID()
    var node: CategoryNode?
    var parentID: EntityID?
    var name = ""
    var isGroup = false
    init(parentID: EntityID? = nil, name: String = "", isGroup: Bool = false) {
        self.parentID = parentID; self.name = name; self.isGroup = isGroup
    }
    init(node: CategoryNode) {
        self.node = node; parentID = node.parentID; name = node.name; isGroup = !node.isLeaf
    }
}

struct CategoryEditorView: View {
    let ledgerID: EntityID
    let kind: TransactionKind
    let context: CategoryEditorContext
    var saved: (EntityID) -> Void
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var name = ""
    @State private var parentID: EntityID?
    @State private var symbolName: String?
    @State private var loaded = false
    @State private var exitRequested = false
    @State private var confirmArchive = false
    @State private var confirmDelete = false
    @State private var error: String?
    @State private var detent: PresentationDetent = .fraction(0.7)
    @FocusState private var nameFocused: Bool
    private var symbol: String { symbolName ?? CategorySymbol.name(for: name) }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (context.isGroup || parentID != nil) }
    private var fieldLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
    }

    private var hasChanges: Bool { loaded && (name != context.name || parentID != context.parentID || symbolName != context.node?.symbolName) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 16) {
                        Image(systemName: symbol).font(.system(size: 28, weight: .medium))
                            .foregroundStyle(Design.primary(scheme)).frame(width: 64, height: 64)
                            .background(Design.selectedFill(scheme), in: RoundedRectangle(cornerRadius: 20))
                            .accessibilityIdentifier("categories.iconPreview").accessibilityLabel(symbol)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("分类名称").font(.caption).foregroundStyle(.secondary)
                            TextField("例如：周末早午餐", text: $name).font(.title3.weight(.medium))
                                .focused($nameFocused).submitLabel(.done).onSubmit { nameFocused = false }
                                .accessibilityIdentifier("categories.name")
                        }
                    }.padding(.top, 8)
                    if !context.isGroup {
                        fieldLayout {
                            Text("所属一级分类").font(.subheadline).foregroundStyle(.secondary)
                            if !typeSize.isAccessibilitySize { Spacer() }
                            Picker("所属一级分类", selection: $parentID) {
                                Text("请选择").tag(EntityID?.none)
                                ForEach(state.store.categories(in: ledgerID, kind: kind).filter { !$0.isLeaf && (!$0.archived || $0.id == context.parentID) }) { group in
                                    Text(group.name).tag(EntityID?.some(group.id))
                                }
                            }.labelsHidden().accessibilityIdentifier("categories.parent")
                        }.frame(minHeight: 44)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        fieldLayout {
                            Text("选择图标").font(.subheadline.weight(.semibold))
                            if !typeSize.isAccessibilitySize { Spacer() }
                            Button("自动匹配") { symbolName = nil; nameFocused = false }
                                .font(.caption).frame(minHeight: 44)
                                .accessibilityIdentifier("categories.icon.auto")
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 64 : 44), spacing: 8)], spacing: 10) {
                            ForEach(CategoryIcon.all) { icon in
                                Button { symbolName = icon.id; nameFocused = false } label: {
                                    Image(systemName: icon.id).font(.system(size: 22, weight: .regular))
                                        .frame(maxWidth: .infinity, minHeight: 46)
                                        .foregroundStyle(symbol == icon.id ? Design.primary(scheme) : .primary)
                                        .background(symbol == icon.id ? Design.selectedFill(scheme) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 13))
                                        .overlay(alignment: .topTrailing) {
                                            if symbol == icon.id { Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(Design.primary(scheme)).offset(x: 2, y: -2) }
                                        }
                                }.buttonStyle(.plain).accessibilityLabel(icon.name)
                                    .accessibilityAddTraits(symbol == icon.id ? [.isSelected] : [])
                                    .accessibilityIdentifier("categories.icon.\(icon.id)")
                            }
                        }
                    }
                    if context.node != nil {
                        Text("改名和调整归属会同步到历史账单，金额不变。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error { Text(error).font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("categories.error") }
                }.padding(.horizontal, 24).padding(.bottom, 16)
            }.scrollDismissesKeyboard(.interactively)
                .background(Color(.systemBackground))
                .safeAreaInset(edge: .bottom) {
                    Button(context.node == nil ? "创建分类" : "保存修改", action: save)
                        .buttonStyle(SolidActionStyle()).disabled(!canSave)
                        .accessibilityIdentifier("categories.save")
                        .padding(.horizontal, 24).padding(.vertical, 12).background(Color(.systemBackground)).opacity(exitRequested ? 0 : 1)
                }
                .navigationTitle(context.node == nil ? (context.isGroup ? "新增一级分类" : "新增二级分类") : "编辑分类")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { nameFocused = false; if hasChanges { exitRequested = true } else { dismiss() } }.accessibilityIdentifier("categories.cancel") }
                    if let node = context.node, !node.archived {
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                Button("归档分类") { nameFocused = false; confirmArchive = true }
                                if state.store.categoryReferenceCount(node.id) == 0 {
                                    Button("删除未使用分类", role: .destructive) { nameFocused = false; confirmDelete = true }
                                }
                            } label: { Image(systemName: "ellipsis").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("更多分类操作")
                        }
                    }
                }
                .alert("归档分类？", isPresented: $confirmArchive) {
                    Button("归档") { removeCategory(permanently: false) }
                    Button("取消", role: .cancel) {}
                } message: { Text("归档后不再用于新记录，历史账单保留。") }
                .alert("删除未使用分类？", isPresented: $confirmDelete) {
                    Button("删除", role: .destructive) { removeCategory(permanently: true) }
                    Button("取消", role: .cancel) {}
                } message: { Text("删除后无法恢复。") }
                .onAppear {
                    guard !loaded else { return }; loaded = true
                    name = context.name; parentID = context.parentID; symbolName = context.node?.symbolName
                    if typeSize.isAccessibilitySize { detent = .large }
                }
        }
        .tint(Design.primary(scheme)).modifier(CleanSheetSurface())
        .modifier(FormExitGuard(isDirty: hasChanges, requested: $exitRequested))
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.fraction(0.7), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: nameFocused) { focused in if focused { detent = .large } }
    }
    private func removeCategory(permanently: Bool) {
        guard let node = context.node else { return }
        let ok = state.perform {
            if permanently { try state.store.deleteCategory(node.id) }
            else { try state.store.archiveCategory(node.id, archived: true) }
        }
        if ok { dismiss(); saved(node.id) } else { error = state.alertError }
    }
    private func save() {
        nameFocused = false
        var id: EntityID?
        let ok = state.perform(nil) {
            if let node = context.node {
                try state.store.editCategory(node.id, name: name, parentID: parentID); id = node.id
            } else {
                id = try state.store.createCategory(ledgerID: ledgerID, kind: kind, parentID: parentID, name: name).id
            }
            if let id { try state.store.setCategorySymbol(id, symbolName: symbolName) }
        }
        if ok, let id { dismiss(); saved(id) } else { error = state.alertError }
    }
}
