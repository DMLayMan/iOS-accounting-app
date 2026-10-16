import CloudKit
import Foundation
import YujiCore

/// CloudKit adapter. The app remains useful without entitlements or an iCloud account.
@MainActor final class CloudKitTransport: CloudTransport {
    let container: CKContainer
    let identifier: String
    let environment: String
    private var lastAccount: String?
    private var downloaded: [CloudAddress: (tag: String?, value: CloudRemote)] = [:]
    #if DEBUG
    /// Native opt-in acceptance can inspect error codes without logging payloads or identities.
    var errorObserver: ((Error) -> Void)?
    #endif
    var configuration: CloudAddress { CloudAddress(container: identifier, environment: environment, zoneName: "") }
    init(identifier: String, environment: String) {
        self.identifier = identifier; self.environment = environment
        container = CKContainer(identifier: identifier)
    }
    static func configured() -> CloudKitTransport? {
        // Never instantiate CKContainer in an unsigned/unprovisioned simulator installation.
        let enabled = Bundle.main.object(forInfoDictionaryKey: "YujiCloudKitEnabled")
        guard (enabled as? Bool == true) || (enabled as? String)?.uppercased() == "YES",
              let id = Bundle.main.object(forInfoDictionaryKey: "YujiCloudKitContainer") as? String,
              id.hasPrefix("iCloud."), !id.contains("$(") else { return nil }
        return CloudKitTransport(identifier: id, environment: Bundle.main.object(forInfoDictionaryKey: "YujiCloudKitEnvironment") as? String ?? "Development")
    }
    func identity(_ recordName: String) -> String { identifier + "|" + environment + "|" + recordName }
    /// CKShare can represent the current participant with Apple's reserved alias.
    /// Resolve it before comparing authors or addressing a member's nickname record.
    static func memberIdentity(_ recordName: String, currentAccount: String, configuration: CloudAddress) -> String {
        recordName == CKCurrentUserDefaultName ? currentAccount : configuration.container + "|" + configuration.environment + "|" + recordName
    }
    func memberIdentity(_ recordName: String, currentAccount: String) -> String {
        Self.memberIdentity(recordName, currentAccount: currentAccount, configuration: configuration)
    }
    func accountID() async throws -> String {
        do {
            switch try await container.accountStatus() {
            case .available: break
            case .noAccount: throw CloudSyncError.notSignedIn
            case .restricted: throw CloudSyncError.invalid("系统限制了 iCloud 访问。请检查家长控制或设备管理设置；本机数据已保留。")
            case .couldNotDetermine, .temporarilyUnavailable: throw CloudSyncError.invalid("iCloud 账号暂时不可用，本机修改已保留，请稍后检查。")
            @unknown default: throw CloudSyncError.offline
            }
            let current = identity(try await container.userRecordID().recordName)
            if current != lastAccount { downloaded.removeAll(); lastAccount = current }
            return current
        } catch { throw mapped(error) }
    }
    func database(_ address: CloudAddress) throws -> CKDatabase {
        guard address.container == identifier, address.environment == environment, address.zoneName.hasPrefix("yuji-book-") else {
            throw CloudSyncError.invalid("iCloud 容器或环境不一致，未访问其他账本。")
        }
        return address.scope == .private ? container.privateCloudDatabase : container.sharedCloudDatabase
    }
    func zoneID(_ address: CloudAddress) -> CKRecordZone.ID { .init(zoneName: address.zoneName, ownerName: address.ownerName) }
    func addresses() async throws -> [CloudAddress] {
        do {
            var values: [CloudAddress] = []
            let own = try await container.privateCloudDatabase.allRecordZones()
            let shared = try await container.sharedCloudDatabase.allRecordZones()
            for (scope, zones) in [(CloudAddress.Scope.private, own), (.shared, shared)] {
                values += zones.filter { $0.zoneID.zoneName.hasPrefix("yuji-book-") }.map {
                    CloudAddress(container: identifier, environment: environment, scope: scope, zoneName: $0.zoneID.zoneName, ownerName: $0.zoneID.ownerName)
                }
            }
            return values
        } catch { throw mapped(error) }
    }
    func fetch(_ address: CloudAddress) async throws -> CloudRemote? {
        do {
            let db = try database(address)
            let recordID = CKRecord.ID(recordName: "ledger", zoneID: zoneID(address))
            let headers = try await db.records(for: [recordID], desiredKeys: ["formatVersion"])
            guard let headerResult = headers[recordID] else { throw CloudSyncError.offline }
            let header = try headerResult.get()
            let writable: Bool
            if address.scope == .private { writable = true }
            else {
                let share = try await share(at: address)
                guard share.currentUserParticipant?.acceptanceStatus == .accepted else { throw CloudSyncError.revoked }
                writable = share.currentUserParticipant?.permission == .readWrite
            }
            if let cached = downloaded[address], cached.tag == header.recordChangeTag {
                var value = cached.value; value.writable = writable; return value
            }
            let record = try await db.record(for: recordID)
            let value = try remote(record, writable: writable)
            downloaded[address] = (record.recordChangeTag, value)
            return value
        } catch {
            if address.scope == .private, let ck = error as? CKError, [.unknownItem, .zoneNotFound].contains(ck.code) { return nil }
            throw mapped(error)
        }
    }
    func remote(_ record: CKRecord, writable: Bool) throws -> CloudRemote {
        guard record.recordType == "YujiLedger", let asset = record["payload"] as? CKAsset, let url = asset.fileURL else {
            throw CloudSyncError.invalid("云端账本内容缺失，未替换本机数据。")
        }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 40_000_000 else { throw CloudSyncError.invalid("云端账本超过本版本的同步大小限制。") }
        let snapshot = try CloudLedgerSnapshot.decode(Data(contentsOf: url))
        let coder = NSKeyedArchiver(requiringSecureCoding: true); record.encodeSystemFields(with: coder); coder.finishEncoding()
        return CloudRemote(snapshot: snapshot, version: coder.encodedData, writable: writable)
    }
    func save(_ snapshot: CloudLedgerSnapshot, at address: CloudAddress, version: Data?) async throws -> CloudRemote {
        try snapshot.validate()
        let bytes = try snapshot.encoded()
        guard bytes.count <= 40_000_000 else { throw CloudSyncError.invalid("账本超过本版本同步限制，本机数据已保留。") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yuji-cloud-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("payload.json"); try bytes.write(to: url, options: .atomic)
        do {
            let db = try database(address)
            if version == nil {
                guard address.scope == .private else { throw CloudSyncError.revoked }
                _ = try await db.save(CKRecordZone(zoneID: zoneID(address)))
            }
            let record: CKRecord
            if let version {
                let coder = try NSKeyedUnarchiver(forReadingFrom: version); coder.requiresSecureCoding = true
                guard let restored = CKRecord(coder: coder), restored.recordID.zoneID == zoneID(address), restored.recordID.recordName == "ledger" else {
                    throw CloudSyncError.invalid("云端版本标识无效，已停止提交。")
                }
                coder.finishDecoding(); record = restored
            } else { record = CKRecord(recordType: "YujiLedger", recordID: .init(recordName: "ledger", zoneID: zoneID(address))) }
            record["payload"] = CKAsset(fileURL: url); record["name"] = snapshot.ledger.name as CKRecordValue
            record["formatVersion"] = 1 as CKRecordValue
            let result = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
            guard let entry = result.saveResults[record.recordID] else { throw CloudSyncError.offline }
            let saved = try entry.get()
            let value = try remote(saved, writable: true)
            downloaded[address] = (saved.recordChangeTag, value)
            return value
        } catch { throw mapped(error) }
    }
    func share(at address: CloudAddress) async throws -> CKShare {
        let db = try database(address)
        guard let value = try await db.record(for: .init(recordName: CKRecordNameZoneWideShare, zoneID: zoneID(address))) as? CKShare else {
            throw CloudSyncError.revoked
        }
        return value
    }
    func prepareShare(_ link: CloudLink) async throws -> CKShare {
        guard link.address.scope == .private, !link.pending, link.incoming == nil else {
            throw CloudSyncError.invalid("请先完成同步，再邀请成员。")
        }
        do { return try await share(at: link.address) }
        catch let error as CKError where error.code == .unknownItem {
            let value = CKShare(recordZoneID: zoneID(link.address))
            value[CKShare.SystemFieldKey.title] = link.cached.ledger.name as CKRecordValue
            value.publicPermission = .none
            do {
                guard let saved = try await container.privateCloudDatabase.save(value) as? CKShare else { throw CloudSyncError.revoked }
                return saved
            }
            catch { throw mapped(error) }
        } catch { throw mapped(error) }
    }
    static func inviteEmail(_ input: String) throws -> String {
        let email = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        let forbidden = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard email.utf8.count <= 254, parts.count == 2,
              !parts[0].isEmpty, !parts[1].isEmpty, parts[1].contains("."),
              email.rangeOfCharacter(from: forbidden) == nil else {
            throw CloudSyncError.invalid("请输入对方使用的 Apple 账户邮箱。")
        }
        return email
    }
    func invite(email input: String, permission: CKShare.ParticipantPermission, to link: CloudLink) async throws -> CKShare {
        let email = try Self.inviteEmail(input)
        guard permission == .readOnly || permission == .readWrite else {
            throw CloudSyncError.invalid("请选择一起记账或仅查看。")
        }
        let owner = try await accountID()
        guard owner == link.accountID else { throw CloudSyncError.invalid("iCloud 账号已变化，请重新确认后邀请。") }
        let share = try await prepareShare(link)
        guard share.publicPermission == .none, share.currentUserParticipant?.role == .owner else {
            throw CloudSyncError.invalid("只有拥有者可以添加此私有账本的成员。")
        }
        do {
            let participant = try await container.shareParticipant(forEmailAddress: email)
            if let id = participant.userIdentity.userRecordID, memberIdentity(id.recordName, currentAccount: owner) == owner {
                throw CloudSyncError.invalid("这是你的 iCloud 账号，无需邀请自己。")
            }
            let accountAfterLookup = try await accountID()
            guard accountAfterLookup == owner else { throw CloudSyncError.invalid("iCloud 账号已变化，请重新确认后邀请。") }
            let existing = share.participants.first { value in
                if let id = participant.userIdentity.userRecordID { return value.userIdentity.userRecordID == id }
                return value.userIdentity.lookupInfo?.emailAddress?.caseInsensitiveCompare(email) == .orderedSame
            }
            if let existing {
                guard existing.permission == permission else {
                    throw CloudSyncError.invalid("对方已在成员列表中，请从管理成员调整权限。")
                }
                return share
            }
            participant.permission = permission
            share.addParticipant(participant)
            try Task.checkCancellation()
            let currentOwner = try await accountID()
            guard currentOwner == owner else { throw CloudSyncError.invalid("iCloud 账号已变化，请重新确认后邀请。") }
            guard let saved = try await container.privateCloudDatabase.save(share) as? CKShare else {
                throw CloudSyncError.invalid("邀请未保存，请重试。")
            }
            return saved
        } catch { throw mapped(error) }
    }
    func accept(_ metadata: CKShare.Metadata) async throws {
        guard metadata.containerIdentifier == identifier,
              metadata.share.recordID.recordName == CKRecordNameZoneWideShare,
              metadata.share.recordID.zoneID.zoneName.hasPrefix("yuji-book-") else {
            throw CloudSyncError.invalid("这不是当前余记容器的账本邀请。")
        }
        do { _ = try await container.accept(metadata) } catch { throw mapped(error) }
    }
    func leave(_ address: CloudAddress) async throws {
        guard address.scope == .shared else { throw CloudSyncError.invalid("拥有者不能用退出成员的方式删除共享账本。") }
        do {
            // Participants leave by deleting their shared CKShare, not the owner's zone.
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID(address))
            _ = try await (try database(address)).deleteRecord(withID: shareID)
            downloaded.removeValue(forKey: address)
        } catch { throw mapped(error) }
    }
    private func mapped(_ error: Error) -> Error {
        #if DEBUG
        errorObserver?(error)
        #endif
        if error is CloudSyncError || error is DomainError { return error }
        guard let ck = error as? CKError else { return CloudSyncError.offline }
        if ck.code == .partialFailure, let errors = ck.partialErrorsByItemID?.values {
            for error in errors { if let sub = error as? CKError, sub.code == .serverRecordChanged { return CloudSyncError.conflict } }
            if let first = errors.first { return mapped(first) }
        }
        switch ck.code {
        case .serverRecordChanged: return CloudSyncError.conflict
        case .notAuthenticated: return CloudSyncError.notSignedIn
        case .permissionFailure, .zoneNotFound, .unknownItem, .userDeletedZone: return CloudSyncError.revoked
        case .quotaExceeded: return CloudSyncError.invalid("iCloud 空间不足，本机修改已保留。请释放空间后重试。")
        case .badContainer, .missingEntitlement: return CloudSyncError.unavailable
        default: return CloudSyncError.offline
        }
    }
}
