import CloudKit
import CryptoKit
import Foundation
import YujiCore

/// Separate records reuse the deployed storage envelope, never the financial JSON asset.
/// This preserves compatibility with clients that only read/write the `ledger` record.
@MainActor extension CloudKitTransport {
    var supportsPeople: Bool { true }

    func myPerson() async throws -> CloudPerson {
        let account = try await accountID()
        let recordID = CKRecord.ID(recordName: "yuji-my-nickname")
        let record = try await personRecord(recordID, database: container.privateCloudDatabase)
        let id = try await container.userRecordID()
        let participant = try? await container.shareParticipant(forUserRecordID: id)
        let name = participant.flatMap { cloudName($0.userIdentity.nameComponents) }
        if let record {
            var person = try decodePerson(record, expectedAccount: account)
            person.cloudName = name ?? person.cloudName
            return person
        }
        return CloudPerson(accountID: account, cloudName: name, revision: "icloud-default-" + digest(name ?? ""))
    }

    func saveMyPerson(_ person: CloudPerson) async throws {
        try await writePerson(person, recordID: .init(recordName: "yuji-my-nickname"), database: container.privateCloudDatabase)
    }

    func people(at address: CloudAddress) async throws -> [CloudPerson] {
        let currentAccount = try await accountID()
        let db = try database(address)
        let value: CKShare
        do { value = try await share(at: address) }
        catch let error as CKError where error.code == .unknownItem && address.scope == .private { return [] }
        var members: [CloudPerson] = []
        let participants = value.participants.filter { $0.acceptanceStatus == .accepted || $0.role == .owner }
        let ids = participants.compactMap { $0.userIdentity.userRecordID }.map {
            memberRecordID(memberIdentity($0.recordName, currentAccount: currentAccount), address: address)
        }
        let records = ids.isEmpty ? [:] : try await db.records(for: ids)
        for participant in participants {
            guard let recordID = participant.userIdentity.userRecordID else { continue }
            let account = memberIdentity(recordID.recordName, currentAccount: currentAccount)
            let id = memberRecordID(account, address: address)
            var record: CKRecord?
            if let result = records[id] {
                do { record = try result.get() }
                catch let error as CKError where error.code == .unknownItem { record = nil }
            }
            if let record {
                var person = try decodePerson(record, expectedAccount: account)
                // Current Apple-provided name is preferable to a previously cached default.
                person.cloudName = cloudName(participant.userIdentity.nameComponents) ?? person.cloudName
                members.append(person)
            } else {
                members.append(CloudPerson(accountID: account, cloudName: cloudName(participant.userIdentity.nameComponents)))
            }
        }
        return members
    }

    func publishMyPerson(_ person: CloudPerson, at address: CloudAddress) async throws {
        let db = try database(address)
        if address.scope == .shared {
            let value = try await share(at: address)
            guard value.currentUserParticipant?.permission == .readWrite else { throw CloudSyncError.revoked }
        }
        try await writePerson(person, recordID: memberRecordID(person.accountID, address: address), database: db)
    }

    private func cloudName(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let name = PersonNameComponentsFormatter.localizedString(from: components, style: .short)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : String(name.prefix(100))
    }
    private func digest(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func memberRecordID(_ account: String, address: CloudAddress) -> CKRecord.ID {
        .init(recordName: "member-" + digest(account), zoneID: zoneID(address))
    }
    private func personRecord(_ id: CKRecord.ID, database: CKDatabase) async throws -> CKRecord? {
        do { return try await database.record(for: id) }
        catch let error as CKError where error.code == .unknownItem { return nil }
    }
    private func decodePerson(_ record: CKRecord, expectedAccount: String) throws -> CloudPerson {
        guard record.recordType == "YujiLedger", record["formatVersion"] as? Int == 1,
              let asset = record["payload"] as? CKAsset, let url = asset.fileURL else {
            throw CloudSyncError.invalid("昵称资料格式暂不支持。")
        }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard let size, size <= 16_384 else { throw CloudSyncError.invalid("昵称资料过大。") }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 16_384 else { throw CloudSyncError.invalid("昵称资料过大。") }
        let person = try JSONDecoder().decode(CloudPerson.self, from: bytes)
        try person.validate(expectedAccount: expectedAccount)
        return person
    }
    private func writePerson(_ person: CloudPerson, recordID: CKRecord.ID, database: CKDatabase) async throws {
        try person.validate(expectedAccount: person.accountID)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("yuji-person-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("person.json")
        let bytes = try JSONEncoder().encode(person)
        guard bytes.count <= 16_384 else { throw CloudSyncError.invalid("昵称资料过大，请简化昵称。") }
        try bytes.write(to: file, options: .atomic)
        for attempt in 0..<3 {
            let current = try await accountID()
            guard current == person.accountID else { throw CloudSyncError.invalid("iCloud 账号已变化，未更新昵称。") }
            let record = try await personRecord(recordID, database: database) ?? CKRecord(recordType: "YujiLedger", recordID: recordID)
            record["payload"] = CKAsset(fileURL: file)
            record["name"] = "member-profile" as CKRecordValue
            record["formatVersion"] = 1 as CKRecordValue
            guard try await accountID() == person.accountID else { throw CloudSyncError.notSignedIn }
            do {
                // The private preference lives in the default zone, which has no atomic-batch capability.
                // A single record still has compare-and-swap protection via its change tag.
                let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
                guard let saved = result.saveResults[recordID] else { throw CloudSyncError.offline }
                _ = try saved.get(); return
            } catch let error as CKError where error.code == .serverRecordChanged && attempt < 2 { continue }
        }
    }
}
