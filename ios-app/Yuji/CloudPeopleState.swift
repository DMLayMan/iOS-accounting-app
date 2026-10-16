import Foundation
import YujiCore

@MainActor extension AppState {
    var myCloudPerson: CloudOwnPerson? {
        store.data.cloudPeople?.own.first { $0.person.accountID == cloudAccountID }
    }
    var myNicknameSummary: String { myCloudPerson?.person.displayName ?? "未设置" }
    var nicknameReadOnlyBooks: [String] {
        currentCloudLinks.filter { !$0.writable }.map { $0.cached.ledger.name }.sorted()
    }

    func personName(_ identity: String?, ledgerID: EntityID, marksSelf: Bool = false) -> String {
        guard let identity else { return "未知记账人" }
        if identity == cloudAccountID {
            let name = myCloudPerson?.person.displayName
            return name.map { marksSelf ? $0 + "（我）" : $0 } ?? "我"
        }
        guard let account = cloudAccountID, let link = cloudLink(for: ledgerID) else { return "共同记账成员" }
        let members = store.data.cloudPeople?.books.first { $0.accountID == account && $0.address == link.address }?
            .members.sorted { $0.accountID < $1.accountID } ?? []
        if let index = members.firstIndex(where: { $0.accountID == identity }) {
            return members[index].displayName ?? "成员 \(index + 1)"
        }
        return "共同记账成员"
    }

    /// Save intent before any await. A failed network request never discards the chosen name.
    @discardableResult func setMyNickname(_ input: String) -> Bool {
        guard cloudAccountReady, let account = cloudAccountID, cloudTransport?.supportsPeople == true else {
            alertError = "请先连接 iCloud，再设置昵称。"; return false
        }
        do {
            let nickname = try CloudPerson.normalizedNickname(input)
            var person = myCloudPerson?.person ?? CloudPerson(accountID: account)
            person.nickname = nickname; person.revision = UUID().uuidString
            var cache = store.data.cloudPeople ?? CloudPeople()
            cache.own.removeAll { $0.person.accountID == account }
            cache.own.append(CloudOwnPerson(person: person, pending: true))
            try persistCloudPeople(cache)
            cloudPeopleIssue = nil; cloudPeopleRefreshedAt = nil
            return true
        } catch { alertError = CloudLedgerMerge.describe(error); return false }
    }

    /// Separate metadata lane; failure must not report a financial sync failure.
    func synchronizePeople(force: Bool = false) async {
        guard storageFailure == nil, cloudAccountReady,
              let account = cloudAccountID, let transport = cloudTransport, transport.supportsPeople else { return }
        if cloudPeopleBusy {
            // A save/retry made during a refresh must not disappear with the stale response.
            if force { cloudPeopleSyncRequested = true }
            return
        }
        if !force, let last = cloudPeopleRefreshedAt, Date().timeIntervalSince(last) < 120 { return }
        cloudPeopleBusy = true
        defer {
            cloudPeopleBusy = false
            if cloudPeopleSyncRequested {
                cloudPeopleSyncRequested = false
                Task { [weak self] in await self?.synchronizePeople(force: true) }
            }
        }
        let epoch = cloudEpoch
        func stillCurrent() -> Bool { epoch == cloudEpoch && account == cloudAccountID }
        do {
            let startingRevision = myCloudPerson?.person.revision
            let person: CloudPerson
            if let own = myCloudPerson, own.pending {
                person = own.person
                try await transport.saveMyPerson(person)
                guard stillCurrent(), myCloudPerson?.person.revision == person.revision else { return }
            } else {
                person = try await transport.myPerson()
                guard stillCurrent(), myCloudPerson?.person.revision == startingRevision else { return }
                try person.validate(expectedAccount: account)
            }
            var cache = store.data.cloudPeople ?? CloudPeople()
            cache.own.removeAll { $0.person.accountID == account }
            cache.own.append(CloudOwnPerson(person: person))
            try persistCloudPeople(cache)

            var deferredReadOnly = false
            var deferredBook = false
            var bookIssue: String?
            for link in currentCloudLinks where link.paused || link.incoming != nil || link.issue != nil {
                if cache.books.first(where: { $0.accountID == account && $0.address == link.address })?.publishedRevision != person.revision {
                    deferredBook = true
                }
            }
            for link in currentCloudLinks where !link.paused && link.incoming == nil && link.issue == nil {
                do {
                    let members = try await transport.people(at: link.address)
                    guard stillCurrent(), myCloudPerson?.person.revision == person.revision else { return }
                    var book = store.data.cloudPeople?.books.first { $0.accountID == account && $0.address == link.address }
                        ?? CloudBookPeople(accountID: account, address: link.address)
                    // Validate all remote presentation data before committing it to the local cache.
                    for member in members { try member.validate(expectedAccount: member.accountID) }
                    book.members = members
                    if book.publishedRevision != person.revision {
                        if link.writable {
                            try await transport.publishMyPerson(person, at: link.address)
                            guard stillCurrent(), myCloudPerson?.person.revision == person.revision else { return }
                            book.publishedRevision = person.revision
                        } else { deferredReadOnly = true }
                    }
                    cache = store.data.cloudPeople ?? CloudPeople()
                    cache.books.removeAll { $0.accountID == account && $0.address == link.address }
                    cache.books.append(book)
                    try persistCloudPeople(cache)
                } catch {
                    guard stillCurrent() else { return }
                    bookIssue = CloudLedgerMerge.describe(error)
                    // An unavailable book must not prevent the other books from receiving the name.
                }
            }
            guard stillCurrent() else { return }
            if let bookIssue { cloudPeopleIssue = "部分账本的昵称待同步：" + bookIssue }
            else if deferredReadOnly { cloudPeopleIssue = "昵称已保存。只读账本暂不能向其他成员更新昵称。" }
            else { cloudPeopleIssue = deferredBook ? "昵称已保存，部分账本将在恢复同步后更新。" : nil }
            cloudPeopleRefreshedAt = Date()
        } catch {
            guard stillCurrent() else { return }
            cloudPeopleIssue = "昵称暂未同步：" + CloudLedgerMerge.describe(error)
            // Bound automatic retries without delaying an explicit retry or a new edit.
            cloudPeopleRefreshedAt = Date()
        }
    }
}
