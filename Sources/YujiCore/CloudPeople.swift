import Foundation

/// Presentation only. The opaque account identity on a transaction never changes with its name.
public struct CloudPerson: Codable, Equatable, Sendable {
    public var kind = "yuji-person"
    public var version = 1
    public var accountID: String
    public var nickname: String?
    public var cloudName: String?
    public var revision: String

    public init(accountID: String, nickname: String? = nil, cloudName: String? = nil, revision: String = UUID().uuidString) {
        self.accountID = accountID; self.nickname = nickname; self.cloudName = cloudName; self.revision = revision
    }
    public static func normalizedNickname(_ input: String) throws -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 20 else { throw CloudSyncError.invalid("昵称最多 20 个字。") }
        guard !value.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || CharacterSet.newlines.contains($0) }) else {
            throw CloudSyncError.invalid("昵称不能包含换行或控制字符。")
        }
        return value.isEmpty ? nil : value
    }
    public func validate(expectedAccount: String) throws {
        guard kind == "yuji-person", version == 1, accountID == expectedAccount,
              !revision.isEmpty, revision.utf8.count <= 100,
              try Self.normalizedNickname(nickname ?? "") == nickname,
              (cloudName?.count ?? 0) <= 100,
              cloudName?.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || CharacterSet.newlines.contains($0) }) != true else {
            throw CloudSyncError.invalid("昵称资料格式不正确，已保留本机信息。")
        }
    }
    public var displayName: String? { nickname ?? cloudName?.nilIfBlank }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

public struct CloudOwnPerson: Codable, Sendable {
    public var person: CloudPerson
    public var pending: Bool
    public init(person: CloudPerson, pending: Bool = false) { self.person = person; self.pending = pending }
}

public struct CloudBookPeople: Codable, Sendable {
    public var accountID: String
    public var address: CloudAddress
    public var members: [CloudPerson]
    /// The global preference revision last projected into this book, never a financial revision.
    public var publishedRevision: String?
    public init(accountID: String, address: CloudAddress, members: [CloudPerson] = [], publishedRevision: String? = nil) {
        self.accountID = accountID; self.address = address; self.members = members; self.publishedRevision = publishedRevision
    }
}

/// Local account-isolated cache/outbox. Excluded from portable backups and financial snapshots.
public struct CloudPeople: Codable, Sendable {
    public var own: [CloudOwnPerson] = []
    public var books: [CloudBookPeople] = []
    public init() {}
}

@MainActor public extension CloudTransport {
    var supportsPeople: Bool { false }
    func myPerson() async throws -> CloudPerson { throw CloudSyncError.unavailable }
    func saveMyPerson(_ person: CloudPerson) async throws { throw CloudSyncError.unavailable }
    func people(at address: CloudAddress) async throws -> [CloudPerson] { [] }
    func publishMyPerson(_ person: CloudPerson, at address: CloudAddress) async throws { throw CloudSyncError.unavailable }
}
