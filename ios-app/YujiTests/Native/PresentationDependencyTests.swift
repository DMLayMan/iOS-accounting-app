import SwiftUI
import UIKit
import XCTest
import YujiCore
@testable import Yuji

@MainActor
final class PresentationDependencyTests: XCTestCase {
    private final class Repository: LedgerRepository {
        var value: LedgerData?
        func load() throws -> LedgerData? { value }
        func save(_ data: LedgerData) throws { value = data }
    }
    private struct Probe: View {
        @EnvironmentObject var state: AppState
        @Environment(\.locale) var locale
        let observed: (AppState, Locale) -> Void
        var body: some View {
            Text("弹层依赖验收").onAppear { observed(state, locale) }
        }
    }
    private struct Item: Identifiable { let id = "invitation" }
    private struct Host: View {
        let state: AppState
        let useItem: Bool
        let probe: Probe
        @State private var presented = true
        @State private var item: Item? = Item()
        var body: some View {
            Group {
                if useItem {
                    Text("host").yujiSheet(item: $item) { _ in probe }
                } else {
                    Text("host").yujiSheet(isPresented: $presented) { probe }
                }
            }.environmentObject(state)
        }
    }
    func testPresentationRootProvidesStateWithoutAnAmbientObject() async {
        let state = AppState(repository: Repository())
        let appeared = expectation(description: "explicit dependency reaches presented content")
        let probe = Probe { received, locale in
            XCTAssertTrue(received === state)
            XCTAssertEqual(locale.identifier, "zh_CN")
            appeared.fulfill()
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIHostingController(rootView: ThemedPresentationRoot(state: state, content: probe))
        window.makeKeyAndVisible(); defer { window.isHidden = true }
        await fulfillment(of: [appeared], timeout: 5)
    }
    func testBooleanSheetCapturesPresentingDependencyOnColdPresentation() async {
        await checkColdPresentation(useItem: false)
    }
    func testItemSheetCapturesPresentingDependencyOnColdPresentation() async {
        await checkColdPresentation(useItem: true)
    }
    private func checkColdPresentation(useItem: Bool) async {
        let state = AppState(repository: Repository())
        let appeared = expectation(description: "cold sheet has state")
        let probe = Probe { received, locale in
            XCTAssertTrue(received === state)
            XCTAssertEqual(locale.identifier, "zh_CN")
            appeared.fulfill()
        }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIHostingController(rootView: Host(state: state, useItem: useItem, probe: probe))
        window.makeKeyAndVisible(); defer { window.isHidden = true }
        await fulfillment(of: [appeared], timeout: 8)
    }
}
