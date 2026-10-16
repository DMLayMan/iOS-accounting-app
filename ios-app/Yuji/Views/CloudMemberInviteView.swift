import CloudKit
import SwiftUI
import UIKit
import YujiCore

struct CloudMemberInviteView: View {
    let ledgerID: EntityID
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var canEdit = true
    @State private var preparing = false
    @State private var invitation: URL?
    @State private var error: String?
    @FocusState private var emailFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                if let invitation {
                    Section {
                        Label("邀请已准备好", systemImage: "checkmark.circle.fill")
                            .font(.title3.weight(.semibold)).foregroundStyle(.tint)
                            .accessibilityIdentifier("cloud.invite.success")
                        Text("链接已复制，发送给对方后即可加入。")
                        Text(email.trimmingCharacters(in: .whitespacesAndNewlines)).font(.subheadline).foregroundStyle(.secondary)
                        Text("仅指定成员可通过链接访问这个账本。")
                            .font(.caption).foregroundStyle(.secondary)
                        ShareLink(item: invitation) { Label("分享邀请", systemImage: "square.and.arrow.up") }
                        Button("再次复制链接") { UIPasteboard.general.url = invitation }
                    }
                } else {
                    Section {
                        TextField("Apple 账户邮箱", text: $email)
                            .keyboardType(.emailAddress).textContentType(.username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($emailFocused).submitLabel(.done).onSubmit { emailFocused = false }
                            .disabled(preparing).accessibilityIdentifier("cloud.invite.email")
                    } header: { Text("邀请谁一起使用") } footer: {
                        Text("填写对方在 iCloud 中使用的邮箱，无需注册余记。")
                    }
                    Section("对方可以") {
                        Picker("成员权限", selection: $canEdit) {
                            Text("一起记账").tag(true)
                            Text("仅查看").tag(false)
                        }.pickerStyle(.segmented).disabled(preparing)
                            .accessibilityIdentifier("cloud.invite.permission")
                        Text(canEdit ? "查看和新增、修改这本账里的记录。" : "查看这本账里的记录，不能新增或修改。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section {
                        Text("仅共享当前账本的账户、分类、流水、备注和预算。其他账本及个人草稿不会共享。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("cloud.invite.error") }
            }
            .navigationTitle("邀请成员").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(invitation == nil ? "取消" : "完成") { emailFocused = false; dismiss() }
                        .disabled(preparing).accessibilityIdentifier("cloud.invite.close")
                }
            }
            .modifier(KeyboardCompletionBar(visible: emailFocused && !preparing, title: "完成输入") { emailFocused = false })
            .safeAreaInset(edge: .bottom) {
                if invitation == nil && !emailFocused {
                    Button(preparing ? "正在准备邀请…" : "邀请并复制链接") { Task { await invite() } }
                        .buttonStyle(SolidActionStyle())
                        .disabled(preparing || !state.cloudAccountReady || (try? CloudKitTransport.inviteEmail(email)) == nil)
                        .accessibilityIdentifier("cloud.invite.create")
                        .padding(20).background(Color(.systemBackground))
                }
            }
        }
        .modifier(CleanSheetSurface())
        .presentationDetents([.fraction(0.7), .large]).presentationDragIndicator(.visible)
        .interactiveDismissDisabled(preparing)
    }

    private func invite() async {
        guard !preparing else { return }
        guard state.cloudAccountReady, let link = state.cloudLink(for: ledgerID),
              let transport = state.cloudTransport as? CloudKitTransport else { error = state.cloudStatus; return }
        preparing = true; error = nil; emailFocused = false
        defer { preparing = false }
        let epoch = state.cloudEpoch
        do {
            let share = try await transport.invite(email: email, permission: canEdit ? .readWrite : .readOnly, to: link)
            let ownerAfterSave = try await transport.accountID()
            guard epoch == state.cloudEpoch, ownerAfterSave == link.accountID else { error = "iCloud 账号已变化，请重新确认后邀请。"; return }
            guard let url = share.url else { error = "邀请已保存，链接暂时不可用。请联网后重试。"; return }
            UIPasteboard.general.url = url
            invitation = url
        } catch { self.error = CloudLedgerMerge.describe(error) }
    }
}
