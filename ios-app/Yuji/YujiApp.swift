import SwiftUI
import UIKit
import YujiCore

@main
struct YujiApp: App {
    @StateObject private var state = YujiApp.makeState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .modifier(AppAccentModifier(settings: state.store.data.settings))
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .preferredColorScheme(colorScheme)
                .onAppear { state.refreshToday() }
                .onChange(of: scenePhase) { phase in
                    if phase == .active { state.refreshToday() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                    state.refreshToday()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    state.refreshToday()
                }
                .alert("提示", isPresented: Binding(get: { state.alertError != nil },
                                                    set: { if !$0 { state.alertError = nil } })) {
                    Button("好", role: .cancel) { state.alertError = nil }
                } message: {
                    Text(state.alertError ?? "")
                }
                .overlay(alignment: .top) {
                    if let toast = state.toast {
                        ToastView(toast: toast, onUndo: {
                            state.undoLastDelete()
                        })
                        .padding(.top, 8)
                        .transition(state.store.data.settings.reduceMotion || UIAccessibility.isReduceMotionEnabled
                                    ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                }
        }
    }

    private static func makeState() -> AppState {
        #if DEBUG
        // An explicit test request must never fall back to the personal repository.
        for key in ["YUJI_STRESS_SESSION", "YUJI_UI_TEST_SESSION"] {
            if let value = ProcessInfo.processInfo.environment[key], UUID(uuidString: value) == nil {
                fatalError("Invalid isolated test session: \(key)")
            }
        }
        if let session = ProcessInfo.processInfo.environment["YUJI_STRESS_SESSION"], UUID(uuidString: session) != nil {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("yuji-stress-\(session).json")
            let repository = JSONFileRepository(url: url)
            do {
                if let mode = ProcessInfo.processInfo.environment["YUJI_TEST_STORE_MODE"] {
                    if mode == "unreadable", !FileManager.default.fileExists(atPath: url.path) {
                        try Data("{unreadable isolated test".utf8).write(to: url)
                    }
                    return isolatedState(repository: repository)
                }
                if !FileManager.default.fileExists(atPath: url.path) {
                    guard let source = Bundle.main.url(forResource: "stats-500", withExtension: "json"),
                          let data = try JSONFileRepository(url: source).load() else {
                        fatalError("Missing isolated stress fixture")
                    }
                    var fixture = data
                    if ProcessInfo.processInfo.environment["YUJI_STRESS_DARK"] == "1" { fixture.settings.appearance = .dark }
                    if ProcessInfo.processInfo.environment["YUJI_CATEGORY_BUDGET_FIXTURE"] == "1" {
                        let store = LedgerStore(data: fixture)
                        try store.setCategoryBudgets(ledgerID: "stress", limits: [
                            .init(period: .month, categoryID: "stress-food", limit: 10_000),
                            .init(period: .month, categoryID: "stress-food-0", limit: 20_000),
                            .init(period: .month, categoryID: "stress-food-1", limit: 5_000),
                            .init(period: .month, categoryID: "stress-home", limit: 100_000),
                            .init(period: .year, categoryID: "stress-food", limit: 10_000),
                            .init(period: .year, categoryID: "stress-food-1", limit: 1_000)
                        ], effective: Day(year: 2026, month: 9, day: 10))
                        fixture = store.data
                    }
                    try repository.save(fixture)
                }
                return isolatedState(repository: repository)
            } catch { fatalError("Stress fixture failed: \(error)") }
        }
        // Native UI tests use a distinct, persistent file per test, never the user's ledger.
        if let session = ProcessInfo.processInfo.environment["YUJI_UI_TEST_SESSION"], UUID(uuidString: session) != nil {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("yuji-ui-\(session).json")
            let repository = JSONFileRepository(url: url)
            if !FileManager.default.fileExists(atPath: url.path) {
                let store = LedgerStore()
                if let ledger = try? store.createLedger(name: "界面验收", startDay: testDay ?? Day(from: Date())) {
                    let parents = store.categories(in: ledger.id, kind: .expense).filter { !$0.isLeaf }
                    if let food = parents.first(where: { $0.name == "餐饮" }) {
                        for name in ["水果", "外卖", "饮品", "买菜", "甜品", "火锅", "聚餐", "夜宵"] {
                            _ = try? store.createCategory(ledgerID: ledger.id, kind: .expense, parentID: food.id, name: name)
                        }
                    }
                    if let fun = parents.first(where: { $0.name == "娱乐" }) {
                        for name in ["旅行休闲", "电影演出"] {
                            _ = try? store.createCategory(ledgerID: ledger.id, kind: .expense, parentID: fun.id, name: name)
                        }
                    }
                    try? repository.save(store.data)
                }
            }
            return isolatedState(repository: repository)
        }
        #endif
        return AppState()
    }

    #if DEBUG
    /// Used only after a valid isolated session UUID has been selected above.
    private static var testDay: Day? {
        guard let value = ProcessInfo.processInfo.environment["YUJI_TEST_TODAY"] else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let day = Day(year: parts[0], month: parts[1], day: parts[2])
        return day.isValid ? day : nil
    }
    private static func isolatedState(repository: LedgerRepository) -> AppState {
        guard let day = testDay else { return AppState(repository: repository) }
        return AppState(repository: repository, clockDay: day, dayProvider: { day })
    }
    #endif

    private var colorScheme: ColorScheme? {
        switch state.store.data.settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct ToastView: View {
    let toast: AppState.Toast
    var onUndo: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .font(.system(size: 14))
                .foregroundColor(.white)
            if toast.message == "已删除" {
                Button("撤销") { onUndo() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white).underline()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.82)))
    }
}
