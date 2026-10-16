import XCTest
@testable import YujiCore

final class CloudPeopleTests: XCTestCase {
    func testNicknameValidationAndEmoji() throws {
        XCTAssertEqual(try CloudPerson.normalizedNickname("  小余  "), "小余")
        XCTAssertNil(try CloudPerson.normalizedNickname("  "))
        XCTAssertEqual(try CloudPerson.normalizedNickname("家人👨‍👩‍👧‍👦"), "家人👨‍👩‍👧‍👦")
        XCTAssertNoThrow(try CloudPerson.normalizedNickname(String(repeating: "余", count: 20)))
        XCTAssertThrowsError(try CloudPerson.normalizedNickname(String(repeating: "余", count: 21)))
        XCTAssertThrowsError(try CloudPerson.normalizedNickname("小\n余"))
        XCTAssertThrowsError(try CloudPerson.normalizedNickname("小\u{0000}余"))
        XCTAssertThrowsError(try CloudPerson(accountID: "a", nickname: "余").validate(expectedAccount: "b"))
    }
    func testLegacyOptionalCacheAndPortableBackupNeverPublishProfiles() throws {
        let store = LedgerStore(); let book = try store.createLedger(name: "本地", startDay: Day(year: 2026, month: 10, day: 15))
        let oldBytes = try JSONEncoder().encode(store.data)
        XCTAssertNil(try JSONDecoder().decode(LedgerData.self, from: oldBytes).cloudPeople)
        var cache = CloudPeople(); cache.own = [.init(person: CloudPerson(accountID: "a", nickname: "私有昵称"), pending: true)]
        var data = store.data; data.cloudPeople = cache
        let snapshot = try CloudLedgerSnapshot(data: data, ledgerID: book.id)
        XCTAssertFalse(String(decoding: try snapshot.encoded(), as: UTF8.self).contains("私有昵称"))
        var backup = try BackupService.makeBackup(from: LedgerStore(data: data))
        XCTAssertNil(backup.data.cloudPeople)
        backup.data.cloudPeople = cache
        XCTAssertNil(try BackupService.validate(backup: backup).cloudPeople)
    }
}
