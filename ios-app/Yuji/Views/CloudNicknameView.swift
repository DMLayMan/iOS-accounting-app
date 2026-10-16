import SwiftUI
import YujiCore

struct CloudNicknameView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var nickname = ""
    @State private var loaded = false
    @State private var edited = false
    @State private var saved = false
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                TextField("输入昵称", text: Binding(get: { nickname }, set: {
                    // Ending text input can write the same value again after Save.
                    guard nickname != $0 else { return }
                    nickname = $0; edited = true; saved = false
                }))
                    .focused($focused).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().submitLabel(.done)
                    .accessibilityLabel("昵称").accessibilityHint("最多 20 个字，留空使用 iCloud 姓名")
                    .accessibilityIdentifier("nickname.input")
                if let name = state.myCloudPerson?.person.cloudName, !name.isEmpty {
                    LabeledContent("iCloud 姓名", value: name)
                }
                if nickname.count > 20 { Text("昵称最多 20 个字，当前 \(nickname.count) 个字。").font(.caption).foregroundStyle(.red) }
                if !nickname.isEmpty {
                    Button("使用 iCloud 姓名") { nickname = ""; edited = true; saved = false; focused = false }
                        .accessibilityIdentifier("nickname.reset")
                }
            } header: { Text("昵称") } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("20 字以内，留空使用 iCloud 姓名。昵称对共享账本成员可见。")
                    if !state.nicknameReadOnlyBooks.isEmpty {
                        Text("只读账本「\(state.nicknameReadOnlyBooks.joined(separator: "、"))」暂不能更新你对外显示的昵称；其他账本和你的 iCloud 昵称仍可保存。")
                            .accessibilityIdentifier("nickname.readonlyScope")
                    }
                }
            }
            Section {
                Label(state.myNicknameSummary, systemImage: "person.crop.circle")
                    .accessibilityIdentifier("nickname.current")
                if state.myCloudPerson?.pending == true {
                    Text("已保存在本机，待同步到 iCloud。")
                        .foregroundStyle(.secondary).accessibilityIdentifier("nickname.pending")
                }
                if saved && state.cloudAccountReady && state.myCloudPerson != nil && state.myCloudPerson?.pending != true && state.cloudPeopleIssue == nil {
                    Label(state.cloudPeopleBusy ? "已保存，正在同步共享账本…" : "昵称已同步", systemImage: state.cloudPeopleBusy ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                        .font(.subheadline).accessibilityIdentifier("nickname.saved")
                }
                if let issue = state.cloudPeopleIssue {
                    Text(issue).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("nickname.issue")
                }
                if !state.cloudAccountReady {
                    Text("请在系统设置登录 iCloud，并检查网络连接。")
                        .foregroundStyle(.secondary)
                }
                Button(state.cloudPeopleBusy ? "正在同步…" : "检查昵称同步") {
                    focused = false
                    Task { await state.refreshCloudAccount(); await state.synchronizePeople(force: true) }
                }.disabled(state.cloudPeopleBusy).accessibilityIdentifier("nickname.sync")
            } header: { Text("当前昵称") } footer: {
                Text("同一 iCloud 账号同步。改名不改变记录的创建人。")
            }
        }
        .navigationTitle("我的昵称").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(saved ? "完成" : "保存") {
                    focused = false
                    if saved { dismiss() }
                    else if state.setMyNickname(nickname) {
                        saved = true
                        nickname = state.myCloudPerson?.person.nickname ?? ""
                        Task { await state.synchronizePeople(force: true) }
                    }
                }.disabled(!saved && (!state.cloudAccountReady || !isValid))
                    .accessibilityIdentifier("nickname.save")
            }
        }
        .onSubmit { focused = false }
        .onAppear { if !loaded { nickname = state.myCloudPerson?.person.nickname ?? ""; loaded = true } }
        .task { await state.refreshCloudAccount(); await state.synchronizePeople(force: true)
            if !edited { nickname = state.myCloudPerson?.person.nickname ?? "" }
        }
    }
    private var isValid: Bool { (try? CloudPerson.normalizedNickname(nickname)) != nil || nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
