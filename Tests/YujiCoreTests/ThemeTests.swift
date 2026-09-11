import XCTest
@testable import YujiCore

final class ThemeTests: XCTestCase {
    func testOldSettingsDecodeWithoutChangingPreferences() throws {
        let json = Data(#"{"hapticsEnabled":false,"reduceMotion":true,"appearance":"dark","icloudEnabled":false}"#.utf8)
        let value = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(value.accentTheme, .sage)
        XCTAssertFalse(value.hapticsEnabled)
        XCTAssertTrue(value.reduceMotion)
        XCTAssertEqual(value.appearance, .dark)
    }

    func testCustomThemeRoundTripAndUnknownThemeFallback() throws {
        var value = AppSettings()
        value.accentTheme = .custom; value.customAccentRGB = 0xFFD400
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded.accentTheme, .custom)
        XCTAssertEqual(decoded.customAccentRGB, 0xFFD400)
        let future = Data(#"{"accentTheme":"future-theme","customAccentRGB":-1}"#.utf8)
        let fallback = try JSONDecoder().decode(AppSettings.self, from: future)
        XCTAssertEqual(fallback.accentTheme, .sage)
        XCTAssertEqual(fallback.customAccentRGB, 0x367961)
    }

    func testPresetAndCustomAccentsMeetTextAndButtonContrast() {
        let samples = AccentTheme.allCases.map { $0.rgb } + [0, 0xFFFFFF, 0xFFFF00, 0x00FFFF, 0xFF00FF]
            + (0..<128).map { ($0 * 130_363) & 0xFFFFFF }
        for hex in samples {
            for dark in [false, true] {
                let color = ThemeRGB(hex: hex).accessibleAccent(dark: dark)
                let surfaces = dark ? [0x000000, 0x1C1C1E, 0x2C2C2E] : [0xFFFFFF, 0xF2F2F7]
                for surface in surfaces {
                    let background = ThemeRGB(hex: surface)
                    XCTAssertGreaterThanOrEqual(color.contrast(with: background), 4.5)
                    XCTAssertGreaterThanOrEqual(color.contrast(with: background.mixed(with: color, fraction: dark ? 0.16 : 0.10)), 4.5)
                }
                XCTAssertGreaterThanOrEqual(color.contrast(with: ThemeRGB(hex: dark ? 0 : 0xFFFFFF)), 4.5)
            }
        }
    }

    func testThemeChangeKeepsExistingFixtureRecordsAndBackupValid() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let original = try XCTUnwrap(JSONFileRepository(url: root.appendingPathComponent("Fixtures/stats-500.json")).load())
        var changed = original
        changed.settings.accentTheme = .plum
        changed.settings.customAccentRGB = 0x123456
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = JSONFileRepository(url: folder.appendingPathComponent("ledger.json"))
        try repo.save(changed)
        let restored = try XCTUnwrap(repo.load())
        XCTAssertEqual(restored.transactions, original.transactions)
        XCTAssertEqual(restored.ledgers, original.ledgers)
        XCTAssertEqual(restored.accounts, original.accounts)
        XCTAssertEqual(restored.settings.accentTheme, .plum)
    }
}
