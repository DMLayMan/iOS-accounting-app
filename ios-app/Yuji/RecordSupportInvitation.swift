import Foundation

/// App-wide local creation history, separate from ledger backups and shared books.
/// Keep the first 100 committed IDs so duplicate event delivery is harmless.
@MainActor
final class RecordSupportInvitation {
    static let threshold = 100
    private struct Journal: Codable {
        var schemaVersion = 1
        var scope: String
        var recordIDs: Set<String> = []
        var consumedAt: Date?
    }
    private let file: URL
    private let write: (Data, URL) throws -> Void
    private var journal: Journal
    private(set) var issue: String?
    var count: Int { journal.recordIDs.count }
    var eligible: Bool { issue == nil && count == Self.threshold && journal.consumedAt == nil }

    init(directory: URL, scope: String = "com.yuji.app/record-support-invitation",
         write: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        file = directory.appendingPathComponent("record-invitation.json")
        self.write = write
        journal = Journal(scope: scope)
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let stored = try JSONDecoder().decode(Journal.self, from: Data(contentsOf: file))
                guard stored.schemaVersion == 1, stored.scope == scope,
                      stored.recordIDs.count <= Self.threshold, !stored.recordIDs.contains("") else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                journal = stored
            } catch { issue = "邀请记录无法读取，已停止自动邀请。" }
        }
    }

    func recordCreated(_ id: String) {
        guard issue == nil, !id.isEmpty, count < Self.threshold,
              journal.consumedAt == nil, !journal.recordIDs.contains(id) else { return }
        var next = journal
        next.recordIDs.insert(id)
        persist(next)
    }

    /// Persist before presenting: dismissal, process death and upgrades cannot replay it.
    @discardableResult
    func consume(at date: Date = Date()) -> Bool {
        guard eligible else { return false }
        var next = journal
        next.consumedAt = date
        return persist(next)
    }

    @discardableResult
    private func persist(_ next: Journal) -> Bool {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try write(JSONEncoder().encode(next), file)
            journal = next
            return true
        } catch {
            // Invitation I/O must never turn a committed ledger save into an error or prompt twice.
            issue = "邀请记录暂时无法保存，已停止自动邀请。"
            return false
        }
    }
}
