#if DEBUG
import Foundation
import YujiCore

/// Deterministic UI adapter, reachable only with an isolated UUID test store.
@MainActor final class SimulatedCloudTransport: CloudTransport {
    let configuration = CloudAddress(container: "iCloud.com.yuji.test", zoneName: "")
    var user = "simulated-account-a"
    var books: [CloudAddress: CloudRemote] = [:]
    var mode: String
    var savedPerson: CloudPerson?
    var supportsPeople: Bool { mode.hasPrefix("people") }
    func myPerson() async throws -> CloudPerson { savedPerson ?? CloudPerson(accountID: user, cloudName: "小余", revision: "default") }
    func saveMyPerson(_ person: CloudPerson) async throws { savedPerson = person }
    func people(at address: CloudAddress) async throws -> [CloudPerson] {
        [savedPerson ?? CloudPerson(accountID: user, cloudName: "小余", revision: "default"),
         CloudPerson(accountID: "simulated-account-b", nickname: "小满", revision: "b")]
    }
    func publishMyPerson(_ person: CloudPerson, at address: CloudAddress) async throws {
        if mode == "peopleReadonly" { throw CloudSyncError.revoked }
    }
    init(mode: String) { self.mode = mode }
    func accountID() async throws -> String { if mode == "signedOut" { throw CloudSyncError.notSignedIn }; return user }
    func addresses() async throws -> [CloudAddress] { if mode == "offline" { throw CloudSyncError.offline }; return Array(books.keys) }
    func fetch(_ address: CloudAddress) async throws -> CloudRemote? {
        if mode == "offline" { throw CloudSyncError.offline }; if mode == "revoked" { throw CloudSyncError.revoked }
        return books[address]
    }
    func save(_ snapshot: CloudLedgerSnapshot, at address: CloudAddress, version: Data?) async throws -> CloudRemote {
        if mode == "offline" { throw CloudSyncError.offline }
        guard books[address]?.version == version else { throw CloudSyncError.conflict }
        guard books[address]?.writable != false else { throw CloudSyncError.revoked }
        let result = CloudRemote(snapshot: snapshot, version: Data(UUID().uuidString.utf8))
        books[address] = result; return result
    }
    func leave(_ address: CloudAddress) async throws { books.removeValue(forKey: address) }
    func seed(_ state: AppState) {
        if supportsPeople { savedPerson = state.store.data.cloudPeople?.own.first { $0.person.accountID == user }?.person }
        guard let book = state.activeLedger, let snapshot = try? CloudLedgerSnapshot(data: state.store.data, ledgerID: book.id) else { return }
        if let links = state.store.data.cloudLinks, !links.isEmpty {
            for link in links where link.accountID == user {
                books[link.address] = CloudRemote(snapshot: link.base ?? link.cached, version: link.version ?? Data("1".utf8), writable: link.writable)
            }
            return
        }
        if mode == "collision" {
            var address = configuration; address.zoneName = "yuji-book-original"
            books[address] = CloudRemote(snapshot:snapshot,version:Data("1".utf8)); return
        }
        guard ["readonly", "conflict", "revoked", "offline", "people", "peopleReadonly", "peopleStats"].contains(mode) else { return }
        let address = CloudAddress(container: configuration.container, scope: .shared, zoneName: "yuji-book-mock", ownerName: "simulated-owner")
        var base = snapshot
        if mode.hasPrefix("people"), let account = snapshot.accounts.first,
           let category = snapshot.categories.first(where: { $0.isLeaf && $0.kind == .expense }) {
            base.transactions = [user, "simulated-account-b"].enumerated().map { index, author in
                var entry = Transaction(ledgerID: book.id, kind: .expense, amountCents: Int64(1200 + index * 500), date: state.today, accountID: account.id, categoryID: category.id)
                entry.authorID = author; entry.lastEditorID = author
                if mode == "peopleStats" { entry.id = EntityID(index == 0 ? "stats-person-a" : "stats-person-b") }
                return entry
            }
            if mode == "peopleStats" {
                base.transactions.append(Transaction(id: "stats-person-unknown", ledgerID: book.id,
                    kind: .expense, amountCents: 800, date: state.today, accountID: account.id, categoryID: category.id))
                var refund = Transaction(id: "stats-person-refund", ledgerID: book.id, kind: .refund,
                    amountCents: 200, date: state.today, accountID: account.id, originalExpenseID: "stats-person-a")
                refund.authorID = "simulated-account-b"; refund.lastEditorID = user
                base.transactions.append(refund)
            }
        }
        if mode == "conflict" {
            let account = snapshot.accounts[0]
            guard let category = snapshot.categories.first(where: { $0.isLeaf && $0.kind == .expense }) else { return }
            base.transactions = [Transaction(ledgerID: book.id, kind: .expense, amountCents: 1000, date: state.today, accountID: account.id, categoryID: category.id)]
        }
        var cached = base, remote = base
        if mode == "conflict" { cached.transactions[0].amountCents = 2000; remote.transactions[0].amountCents = 3000 }
        let writable = !["readonly", "peopleReadonly"].contains(mode)
        books[address] = CloudRemote(snapshot: remote, version: Data("1".utf8), writable: writable)
        var data = state.store.data
        data.cloudLinks = [CloudLink(accountID: user, address: address, cached: cached, base: base, version: Data("1".utf8), writable: writable)]
        try? CloudWorkspace.install(cached, in: &data)
        _ = state.commitCloudData(data)
    }
}
#endif

extension AppState {
    var isCloudSimulation: Bool {
        #if DEBUG
        return cloudTransport is SimulatedCloudTransport
        #else
        return false
        #endif
    }
}
