import Foundation
import YujiCore

enum CloudEnableResult { case enabled(EntityID), requiresIndependentCopy, failed }

@MainActor extension AppState {
    var currentCloudLinks: [CloudLink] { (store.data.cloudLinks ?? []).filter { $0.accountID == cloudAccountID } }
    func cloudLink(for ledgerID: EntityID) -> CloudLink? { currentCloudLinks.first { $0.cached.ledger.id == ledgerID } }
    func cloudBookStatus(_ ledgerID: EntityID) -> String {
        guard let link = cloudLink(for: ledgerID) else { return "仅保存在本机" }
        if !cloudAccountReady { return "iCloud 暂不可用 · 本机数据已保留" }
        if link.incoming != nil { return "有冲突待处理 · 本机修改已保留" }
        if link.issue != nil { return "同步需要处理 · 本机数据已保留" }
        if link.paused { return "自动同步已暂停" }
        if link.pending || link.lastSync == nil { return "本机已保存 · 待同步" }
        return link.writable ? "已同步到 iCloud" : "共享账本 · 仅可查看"
    }
    func canEditLedger(_ ledgerID: EntityID) -> Bool {
        guard let link = cloudLink(for: ledgerID) else { return true }
        return link.writable && link.incoming == nil
    }
    func configureCloud(_ transport: CloudTransport?) { cloudTransport = transport; cloudAccountReady = false; cloudStatus = transport == nil ? CloudSyncError.unavailable.message : "正在检查 iCloud…" }
    func invalidateCloudAccount() {
        startupCloudSelection = nil
        cloudEpoch += 1; cloudDebounce?.cancel(); cloudAccountID = nil; cloudAccountReady = false
        cloudPeopleIssue = nil; cloudPeopleRefreshedAt = nil; cloudPeopleSyncRequested = false
        var data = store.data
        do { try CloudWorkspace.parkAll(&data) } catch { blockCloudWorkspace(data, reason: "云端缓存无法隔离，请恢复本地备份。"); return }
        if !commitCloudData(data) {
            // Do not expose a previous identity when disk space is unavailable.
            blockCloudWorkspace(data, reason: "账号已改变，缓存已隐藏；暂时无法保存，请释放空间后重新读取。")
        }
        cloudStatus = "正在重新检查 iCloud 账号…"
    }
    func refreshCloudAccount() async {
        guard let transport = cloudTransport, !cloudRefreshing, storageFailure == nil else { return }
        cloudRefreshing = true; defer { cloudRefreshing = false }
        cloudAccountReady = false
        let epoch = cloudEpoch
        do {
            let account = try await transport.accountID()
            guard epoch == cloudEpoch else { return }
            if account != cloudAccountID || store.data.activeCloudAccountID != account {
                var data = store.data; try CloudWorkspace.activate(account, in: &data)
                if let selection = startupCloudSelection, selection.accountID == account,
                   data.ledgers.contains(where: { $0.id == selection.ledgerID }) {
                    data.activeLedgerID = selection.ledgerID
                }
                guard commitCloudData(data) else { return }
                startupCloudSelection = nil
                cloudAccountID = account; cloudEpoch += 1
            }
            cloudAccountReady = true; cloudStatus = "iCloud 已登录"
        } catch {
            guard epoch == cloudEpoch else { return }
            if (error as? CloudSyncError) == .notSignedIn { invalidateCloudAccount() }
            cloudStatus = CloudLedgerMerge.describe(error)
        }
    }
    func stampCloudChanges(_ data: inout LedgerData, previous: LedgerData) {
        guard let account = cloudAccountID else { return }
        let linked = Set(currentCloudLinks.map { $0.cached.ledger.id })
        let old = Dictionary(previous.transactions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for i in data.transactions.indices where linked.contains(data.transactions[i].ledgerID) {
            let value = data.transactions[i]
            if old[value.id] != value {
                // Editing cannot rewrite provenance, including unknown creators on legacy entries.
                if let existing = old[value.id] { data.transactions[i].authorID = existing.authorID }
                else { data.transactions[i].authorID = account }
                data.transactions[i].lastEditorID = account
            }
        }
    }
    func scheduleCloudSync() {
        guard cloudTransport != nil, cloudAccountID != nil else { return }
        cloudDebounce?.cancel()
        cloudDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.synchronizeCloud()
        }
    }
    @discardableResult func enableCloud(for ledgerID: EntityID, independentCopy: Bool = false) async -> CloudEnableResult {
        await refreshCloudAccount()
        guard !cloudBusy, cloudAccountReady, let account = cloudAccountID, let transport = cloudTransport else { return .failed }
        cloudBusy = true; defer { cloudBusy = false }
        let epoch = cloudEpoch
        do {
            guard cloudLink(for: ledgerID) == nil else { return .enabled(ledgerID) }
            if !independentCopy {
                // A portable restore keeps IDs; never bind it to a second cloud zone with the same identity.
                for address in try await transport.addresses() {
                    let remote = try await transport.fetch(address)
                    guard epoch == cloudEpoch, account == cloudAccountID else { return .failed }
                    if remote?.snapshot.ledger.id == ledgerID { return .requiresIndependentCopy }
                }
            }
            guard epoch == cloudEpoch, account == cloudAccountID else { return .failed }
            let source = try CloudLedgerSnapshot(data: store.data, ledgerID: ledgerID)
            let book = independentCopy ? try CloudWorkspace.localCopy(source, name: source.ledger.name + "（iCloud 副本）") : source
            var address = transport.configuration; address.zoneName = "yuji-book-" + UUID().uuidString
            var data = store.data
            if independentCopy {
                try CloudWorkspace.install(book, in: &data)
                if let draft = data.drafts.first(where: { $0.ledgerID == ledgerID }) { data.drafts.append(CloudWorkspace.localDraftCopy(draft, from: source, to: book)) }
                data.activeLedgerID = book.ledger.id
            }
            data.cloudLinks = (data.cloudLinks ?? []) + [CloudLink(accountID: account, address: address, cached: book)]
            guard commitCloudData(data) else { return .failed }
            cloudBusy = false
            scheduleCloudSync()
            await synchronizeCloud()
            return .enabled(book.ledger.id)
        } catch { cloudStatus = CloudLedgerMerge.describe(error); alertError = cloudStatus; return .failed }
    }
    /// Foreground refresh, explicit retry and debounced writes share this single serialized lane.
    func synchronizeCloud(forceLedgerID: EntityID? = nil) async {
        guard cloudAccountReady, !cloudBusy, storageFailure == nil, let transport = cloudTransport, let account = cloudAccountID else { return }
        cloudBusy = true; defer { cloudBusy = false }
        let epoch = cloudEpoch
        do {
            let discovered = try await transport.addresses()
            guard epoch == cloudEpoch, account == cloudAccountID else { return }
            for address in discovered where address.zoneName.hasPrefix("yuji-book-") {
                if !(store.data.cloudLinks ?? []).contains(where: { $0.accountID == account && $0.address == address }) {
                    guard let remote = try await transport.fetch(address), epoch == cloudEpoch else { continue }
                    var data = store.data
                    if data.ledgers.contains(where: { $0.id == remote.snapshot.ledger.id }) || (data.cloudLinks ?? []).contains(where: { $0.accountID == account && $0.cached.ledger.id == remote.snapshot.ledger.id }) {
                        cloudStatus = "云端账本标识与现有数据冲突，未覆盖。"; continue
                    }
                    data.cloudLinks = (data.cloudLinks ?? []) + [CloudLink(accountID: account, address: address, cached: remote.snapshot, base: remote.snapshot, version: remote.version, writable: remote.writable)]
                    try CloudWorkspace.install(remote.snapshot, in: &data)
                    guard commitCloudData(data) else { return }
                }
            }
            for address in currentCloudLinks.filter({ !$0.paused || $0.cached.ledger.id == forceLedgerID }).map(\.address) {
                guard epoch == cloudEpoch, account == cloudAccountID else { return }
                do { try await synchronizeBook(address, transport: transport, account: account, epoch: epoch, allowPaused: forceLedgerID != nil) }
                catch {
                    guard epoch == cloudEpoch else { return }
                    var data = store.data
                    if let i = data.cloudLinks?.firstIndex(where: { $0.accountID == account && $0.address == address }) {
                        data.cloudLinks?[i].issue = CloudLedgerMerge.describe(error)
                        if (error as? CloudSyncError) == .revoked { data.cloudLinks?[i].writable = false }
                        _ = commitCloudData(data)
                    }
                    cloudStatus = CloudLedgerMerge.describe(error)
                }
            }
            if epoch == cloudEpoch, !currentCloudLinks.contains(where: { $0.issue != nil }) {
                cloudStatus = currentCloudLinks.isEmpty ? "iCloud 已登录" : (currentCloudLinks.contains(where: { $0.paused }) ? "部分账本已暂停自动同步" : (currentCloudLinks.contains(where: { $0.pending }) ? "本机已保存，仍有修改待同步" : "同步已完成"))
            }
            await synchronizePeople()
        } catch {
            if epoch == cloudEpoch {
                let reason = CloudLedgerMerge.describe(error)
                var data = store.data
                for i in (data.cloudLinks ?? []).indices where data.cloudLinks?[i].accountID == account && (data.cloudLinks?[i].paused == false || data.cloudLinks?[i].cached.ledger.id == forceLedgerID) {
                    data.cloudLinks?[i].issue = reason
                }
                _ = commitCloudData(data)
                cloudStatus = reason
            }
        }
    }
    private func synchronizeBook(_ address: CloudAddress, transport: CloudTransport, account: String, epoch: Int, allowPaused: Bool) async throws {
        for _ in 0..<3 {
            let remote = try await transport.fetch(address)
            guard epoch == cloudEpoch, account == cloudAccountID,
                  let link = currentCloudLinks.first(where: { $0.address == address }) else { return }
            if link.paused && !allowPaused { return }
            let local = try CloudLedgerSnapshot(data: store.data, ledgerID: link.cached.ledger.id)
            var candidate = local
            if let remote {
                guard remote.snapshot.ledger.id == local.ledger.id else { throw CloudSyncError.invalid("云端账本身份不一致，已停止同步。") }
                let merged: CloudLedgerMerge.Result
                if let base = link.base { merged = try CloudLedgerMerge.merge(base: base, local: local, remote: remote.snapshot) }
                else { merged = .init(snapshot: local, conflicts: local.matches(remote.snapshot) ? [] : ["初次同步发现不同版本"]) }
                if !merged.conflicts.isEmpty || (!remote.writable && !local.matches(link.base ?? remote.snapshot)) {
                    var data = store.data
                    guard let i = data.cloudLinks?.firstIndex(where: { $0.accountID == account && $0.address == address }) else { return }
                    data.cloudLinks?[i].incoming = remote.snapshot; data.cloudLinks?[i].version = remote.version
                    data.cloudLinks?[i].writable = remote.writable
                    data.cloudLinks?[i].issue = (merged.conflicts.isEmpty ? ["权限已变为只读，存在未同步修改"] : merged.conflicts).joined(separator: "；")
                    _ = commitCloudData(data); cloudStatus = "有冲突待处理"; return
                }
                candidate = merged.snapshot
            } else if link.base != nil { throw CloudSyncError.revoked }
            try candidate.validate()
            let accepted: CloudRemote
            if let remote, candidate.matches(remote.snapshot) { accepted = remote }
            else {
                do { accepted = try await transport.save(candidate, at: address, version: remote?.version) }
                catch CloudSyncError.conflict { continue }
            }
            guard epoch == cloudEpoch, account == cloudAccountID else { return }
            // New local edits made during a network await are merged against the exact sent candidate.
            let latest = try CloudLedgerSnapshot(data: store.data, ledgerID: local.ledger.id)
            let afterFlight = try CloudLedgerMerge.merge(base: local, local: latest, remote: accepted.snapshot)
            var data = store.data
            guard let i = data.cloudLinks?.firstIndex(where: { $0.accountID == account && $0.address == address }) else { return }
            if !afterFlight.conflicts.isEmpty {
                data.cloudLinks?[i].incoming = accepted.snapshot; data.cloudLinks?[i].version = accepted.version
                data.cloudLinks?[i].issue = "同步期间又修改了相同内容，两个版本都已保留。"
            } else {
                try CloudWorkspace.install(afterFlight.snapshot, in: &data)
                data.cloudLinks?[i].cached = afterFlight.snapshot; data.cloudLinks?[i].base = accepted.snapshot
                data.cloudLinks?[i].version = accepted.version; data.cloudLinks?[i].writable = accepted.writable
                data.cloudLinks?[i].incoming = nil; data.cloudLinks?[i].issue = nil; data.cloudLinks?[i].lastSync = Date()
                try CloudWorkspace.capture(&data)
            }
            guard commitCloudData(data) else { return }
            if cloudLink(for: local.ledger.id)?.pending == true { scheduleCloudSync() }
            return
        }
        throw CloudSyncError.conflict
    }
    func setCloudPaused(_ ledgerID: EntityID, paused: Bool) {
        var data = store.data
        guard let i = data.cloudLinks?.firstIndex(where: { $0.cached.ledger.id == ledgerID && $0.accountID == cloudAccountID }) else { return }
        data.cloudLinks?[i].paused = paused
        if commitCloudData(data), !paused { scheduleCloudSync() }
    }
    /// Resolving never discards unsent financial data: keep an independent copy before adopting remote.
    func resolveCloudConflict(_ ledgerID: EntityID) -> Bool {
        do {
            var data = store.data
            guard let i = data.cloudLinks?.firstIndex(where: { $0.cached.ledger.id == ledgerID && $0.accountID == cloudAccountID }),
                  let incoming = data.cloudLinks?[i].incoming, let cached = data.cloudLinks?[i].cached else { return false }
            let copy = try CloudWorkspace.localCopy(cached, name: cached.ledger.name + "（未同步副本）")
            let draft = data.drafts.first { $0.ledgerID == ledgerID } ?? data.cloudLinks?[i].unresolvedDraft
            try CloudWorkspace.install(copy, in: &data); try CloudWorkspace.install(incoming, in: &data)
            if let draft { data.drafts.append(CloudWorkspace.localDraftCopy(draft, from: cached, to: copy)) }
            data.cloudLinks?[i].cached = incoming; data.cloudLinks?[i].base = incoming
            data.cloudLinks?[i].incoming = nil; data.cloudLinks?[i].issue = nil; data.cloudLinks?[i].lastSync = Date()
            data.cloudLinks?[i].unresolvedDraft = nil
            data.activeLedgerID = ledgerID
            return commitCloudData(data)
        } catch { alertError = CloudLedgerMerge.describe(error); return false }
    }
    func preserveCloudCopy(_ ledgerID: EntityID) -> Bool {
        do {
            guard let link = cloudLink(for: ledgerID) else { return false }
            var data = store.data
            let copy = try CloudWorkspace.localCopy(link.cached, name: link.cached.ledger.name + "（本地副本）")
            try CloudWorkspace.install(copy, in: &data); data.activeLedgerID = copy.ledger.id
            if let draft = link.localDraft ?? link.unresolvedDraft { data.drafts.append(CloudWorkspace.localDraftCopy(draft, from: link.cached, to: copy)) }
            return commitCloudData(data)
        } catch { alertError = CloudLedgerMerge.describe(error); return false }
    }
    func leaveCloudBook(_ ledgerID: EntityID) async -> Bool {
        guard cloudAccountReady, !cloudBusy, let link = cloudLink(for: ledgerID), link.address.scope == .shared, let transport = cloudTransport else { return false }
        cloudBusy = true; defer { cloudBusy = false }
        let epoch = cloudEpoch
        // Save a local copy before touching the remote membership, including on a failed leave request.
        guard preserveCloudCopy(ledgerID) else { return false }
        do {
            try await transport.leave(link.address)
            guard epoch == cloudEpoch else { return false }
            var data = store.data; CloudWorkspace.remove(ledgerID, from: &data)
            data.cloudLinks?.removeAll { $0.accountID == link.accountID && $0.address == link.address }
            return commitCloudData(data)
        } catch { cloudStatus = CloudLedgerMerge.describe(error); return false }
    }
}
