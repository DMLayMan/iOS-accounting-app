import CloudKit
import SwiftUI
import YujiCore

struct CloudBookView: View {
    let ledgerID: EntityID
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var share: CKShare?
    @State private var showingShare = false
    @State private var showingInvite = false
    @State private var message: String?
    @State private var preparing = false
    @State private var confirmEnable = false
    @State private var confirmCloudCopy = false
    @State private var confirmResolve = false
    @State private var confirmLeave = false
    @State private var participants: [CKShare.Participant] = []
    private var link: CloudLink? { state.cloudLink(for: ledgerID) }
    private var name: String { state.store.ledger(ledgerID)?.name ?? link?.cached.ledger.name ?? "账本" }
    var body: some View {
        List {
            Section {
                Label(name, systemImage: link == nil ? "book.closed" : "person.2").font(.title2.weight(.semibold))
                Label(status, systemImage: link == nil ? "internaldrive" : "icloud")
                    .foregroundStyle(.secondary).accessibilityElement(children: .combine).accessibilityIdentifier("cloud.status")
                if let link, let date = link.lastSync { Text("最近同步 \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
            }
            if !state.cloudAccountReady {
                Section {
                    Text(state.cloudStatus).accessibilityIdentifier("cloud.accountMessage")
                    Button("检查 iCloud") { Task { await refresh() } }.disabled(state.cloudBusy).accessibilityIdentifier("cloud.retry")
                } footer: { Text("使用系统 iCloud 账号，无需注册余记。纯本地账本可以继续使用。") }
            }
            if let link {
                if link.unresolvedDraft != nil {
                    Section { Text("旧草稿引用的分类或账户已在云端删除。草稿内容已保留，生成本地副本后可继续填写。")
                        Button("保留草稿到本地副本") { if state.preserveCloudCopy(ledgerID) { message = "草稿已保留到本地副本。" } }
                    }
                }
                if let issue = link.issue {
                    Section("需要处理") {
                        Text(issue).foregroundStyle(.secondary).accessibilityIdentifier("cloud.issue")
                        if link.incoming != nil {
                            NavigationLink("比较两个版本") { CloudConflictView(ledgerID: ledgerID) }
                                .accessibilityIdentifier("cloud.compare")
                            Button("保留本机副本并采用云端") { confirmResolve = true }.accessibilityIdentifier("cloud.resolve")
                        } else {
                            Button("保留独立的本地副本") { if state.preserveCloudCopy(ledgerID) { message = "已保留本地副本，可从切换账本查看。" } }
                        }
                    }
                }
                Section {
                    Button(state.cloudBusy ? "正在同步…" : "立即同步") { Task { await refresh() } }
                        .disabled(state.cloudBusy).accessibilityIdentifier("cloud.sync")
                    Toggle("暂停自动同步", isOn: Binding(get: { state.cloudLink(for: ledgerID)?.paused ?? false }, set: { paused in
                        Task { @MainActor in state.setCloudPaused(ledgerID, paused: paused) }
                    }))
                        .accessibilityIdentifier("cloud.pause")
                    if link.pending { Text("有本机修改待上传").foregroundStyle(.secondary).accessibilityIdentifier("cloud.pending") }
                } header: { Text("同步") } footer: { Text("离线修改先保存在本机。打开 App、返回前台及记账后会同步；此页可立即刷新。") }
                Section {
                    Label(link.address.scope == .private ? "我是拥有者" : (link.writable ? "我可以共同记账" : "我仅可查看"), systemImage: link.writable ? "pencil" : "eye")
                        .accessibilityElement(children: .combine).accessibilityIdentifier("cloud.permission")
                    if !participants.isEmpty {
                        ForEach(Array(participants.enumerated()), id: \.offset) { index, participant in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(participantName(participant, index: index))
                                    Text(participant.role == .owner ? "拥有者" : (participant.acceptanceStatus == .accepted ? "已加入" : "等待接受邀请")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(participant.permission == .readWrite ? "可编辑" : "只读").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if link.address.scope == .private {
                        Button { showingInvite = true } label: { Label("邀请成员", systemImage: "person.badge.plus") }
                            .disabled(preparing || state.cloudBusy || !state.cloudAccountReady || link.pending || state.isCloudSimulation)
                            .accessibilityIdentifier("cloud.invite")
                    }
                    Button(link.address.scope == .private ? "管理成员" : "查看共享成员") { Task { await prepareShare() } }
                        .disabled(preparing || state.cloudBusy || !state.cloudAccountReady || (link.pending && link.address.scope == .private) || state.isCloudSimulation)
                        .accessibilityIdentifier("cloud.members")
                    if link.address.scope == .shared { Button("退出共享账本", role: .destructive) { confirmLeave = true }.disabled(state.cloudBusy || !state.cloudAccountReady).accessibilityIdentifier("cloud.leave") }
                } header: { Text("成员与权限") } footer: { Text("仅分享这个账本的账户、分类、流水、备注和预算。个人草稿、主题及其他账本不会共享。成员权限由拥有者管理。") }
            } else if state.cloudAccountReady {
                Section {
                    Button { confirmEnable = true } label: { Label("开启 iCloud 同步", systemImage: "icloud.and.arrow.up") }
                        .disabled(state.cloudBusy).accessibilityIdentifier("cloud.enable")
                } footer: { Text("开启后可在同一 iCloud 账号的设备上使用，再邀请其他账号共同记账。现有记录会上传到你的 iCloud。") }
            }
            if let message { Section { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("cloud.message") } }
            #if DEBUG
            if state.isCloudSimulation {
                Section { Text("自测模式 · 使用隔离的模拟云端，不会连接或上传 iCloud。").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("cloud.simulated") }
            }
            #endif
        }.navigationTitle("同步与成员").navigationBarTitleDisplayMode(.inline)
            .task { await state.refreshCloudAccount(); await loadMembers() }
            .yujiSheet(isPresented: $showingInvite, onDismiss: { Task { await loadMembers() } }) {
                CloudMemberInviteView(ledgerID: ledgerID)
            }
            .yujiSheet(isPresented: $showingShare, onDismiss: { Task { await refresh(); await loadMembers() } }) {
                if let share, let driver = state.cloudTransport as? CloudKitTransport {
                    CloudSharingView(share: share, container: driver.container, title: name) { error in
                        if let error { message = error }
                        Task { await refresh(); await loadMembers() }
                    }
                }
            }
            .alert("开启此账本的 iCloud 同步？", isPresented: $confirmEnable) {
                Button("取消", role: .cancel) { }
                Button("开启同步") { Task { await enable() } }
            } message: { Text("这个账本的账户、分类、流水、备注和预算将保存到你的 iCloud。尚不会邀请其他人。") }
            .alert("云端已有同源账本", isPresented: $confirmCloudCopy) {
                Button("取消", role: .cancel) { }
                Button("另建副本并同步") { Task { await enable(independentCopy: true) } }
            } message: { Text("可能来自以前的备份。原本地账本和原云端账本都保留；将另建独立的 iCloud 副本，不覆盖共同账本。") }
            .alert("保留本机副本并采用云端？", isPresented: $confirmResolve) {
                Button("取消", role: .cancel) { }
                Button("保留副本并处理") { if state.resolveCloudConflict(ledgerID) { message = "本机修改已保存在独立账本，当前共享账本采用云端版本。" } }
            } message: { Text("未同步修改会另存为“未同步副本”，不再自动上传。共享账本恢复为云端版本，两个版本都保留。") }
            .alert("退出共享账本？", isPresented: $confirmLeave) {
                Button("取消", role: .cancel) { }
                Button("保留副本并退出", role: .destructive) { Task { if await state.leaveCloudBook(ledgerID) { dismiss() } } }
            } message: { Text("先保存独立的本地副本，再退出共享。拥有者和其他成员的账本不受影响。") }
    }
    private var status: String {
        state.cloudBookStatus(ledgerID)
    }
    private func enable(independentCopy: Bool = false) async {
        switch await state.enableCloud(for: ledgerID, independentCopy: independentCopy) {
        case .requiresIndependentCopy: confirmCloudCopy = true
        case .enabled(let id): if id != ledgerID { dismiss() }
        case .failed: break
        }
    }
    private func refresh() async { await state.refreshCloudAccount(); await state.synchronizeCloud(forceLedgerID: ledgerID) }
    private func loadMembers() async {
        await state.synchronizePeople(force: true)
        guard state.cloudAccountReady, let link, let driver = state.cloudTransport as? CloudKitTransport else { return }
        if let share = try? await driver.share(at: link.address) { participants = share.participants }
    }
    private func prepareShare() async {
        guard state.cloudAccountReady, let link, let driver = state.cloudTransport as? CloudKitTransport else { return }
        preparing = true; defer { preparing = false }
        do { share = link.address.scope == .private ? try await driver.prepareShare(link) : try await driver.share(at: link.address); showingShare = true }
        catch { message = CloudLedgerMerge.describe(error) }
    }
    private func participantName(_ participant: CKShare.Participant, index: Int) -> String {
        if let id = participant.userIdentity.userRecordID?.recordName, let driver = state.cloudTransport as? CloudKitTransport,
           let account = state.cloudAccountID {
            let name = state.personName(driver.memberIdentity(id, currentAccount: account), ledgerID: ledgerID, marksSelf: true)
            if name != "共同记账成员" { return name }
        }
        if let components = participant.userIdentity.nameComponents {
            let text = PersonNameComponentsFormatter.localizedString(from: components, style: .short)
            if !text.isEmpty { return text }
        }
        if let email = participant.userIdentity.lookupInfo?.emailAddress, !email.isEmpty { return email }
        return participant.role == .owner ? "拥有者" : "成员 \(index + 1)"
    }
}

struct CloudConflictView: View {
    let ledgerID: EntityID
    @EnvironmentObject private var state: AppState
    @State private var visibleCount = 30
    var body: some View {
        List {
            if let link = state.cloudLink(for: ledgerID), let incoming = link.incoming {
                Section {
                    Text(link.issue ?? "两个版本需要处理").foregroundStyle(.secondary)
                    Text("逐项比较本机与云端的不同内容；相同内容已省略。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let comparison = try? CloudSnapshotComparison(local: link.cached, remote: incoming,
                    personName: { state.personName($0, ledgerID: ledgerID, marksSelf: true) }) {
                    Section("共 \(comparison.changes.count) 项不同") {
                        if comparison.changes.isEmpty {
                            Text("可见业务内容一致。上方提示可能涉及记录间的数据关系；处理前仍会保留本机副本。")
                        }
                        ForEach(comparison.changes.prefix(visibleCount)) { change in
                            VStack(alignment: .leading, spacing: 16) {
                                Text(change.title).font(.headline)
                                ForEach(change.fields) { field in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(field.title).font(.subheadline.weight(.semibold))
                                        value("本机", field.local, isSymbol: field.id == "symbolName")
                                        value("云端", field.remote, isSymbol: field.id == "symbolName")
                                    }.accessibilityElement(children: .combine)
                                }
                            }.padding(.vertical, 8).accessibilityIdentifier("cloud.diff." + change.id)
                        }
                        if comparison.changes.count > visibleCount {
                            Button("继续查看差异（剩余 \(comparison.changes.count - visibleCount) 项）") { visibleCount += 30 }
                        }
                    }.accessibilityIdentifier("cloud.differences")
                } else {
                    Section { Text("暂时无法生成差异比较，两个版本仍完整保留。请返回后重试。") }
                }
                Section { Text("保留本机副本并采用云端后，本机所有未同步内容仍可从独立账本查看，不会自动覆盖其他成员的记录。") }
            }
        }.navigationTitle("版本比较").navigationBarTitleDisplayMode(.inline)
    }
    private func value(_ side: String, _ text: String, isSymbol: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(side).font(.caption).foregroundStyle(.secondary)
            if isSymbol, UIImage(systemName: text) != nil {
                Image(systemName: text).font(.title2).accessibilityLabel("分类图标：" + text)
            } else {
                Text(text).font(.subheadline).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct CloudOverviewView: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        List {
            Section {
                Label(state.cloudAccountReady ? "iCloud 已登录" : "iCloud 暂不可用", systemImage: "icloud")
                Text(state.cloudStatus).font(.subheadline).foregroundStyle(.secondary)
                Button("检查账号与同步") { Task { await state.refreshCloudAccount(); await state.synchronizeCloud() } }.disabled(state.cloudBusy)
            }
            Section("我的账本") {
                ForEach(state.store.data.ledgers) { book in
                    NavigationLink { CloudBookView(ledgerID: book.id) } label: {
                        HStack { Text(book.name); Spacer(); Text(state.cloudLink(for: book.id) == nil ? "本机" : "iCloud").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }.navigationTitle("iCloud 与共享").navigationBarTitleDisplayMode(.inline)
    }
}
