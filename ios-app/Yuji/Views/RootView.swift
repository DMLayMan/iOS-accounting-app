import SwiftUI
import UIKit
import YujiCore

struct RootView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var tab: Tab = .ledger
    @State private var showEntry = false

    enum Tab { case ledger, feed, entry, stats, me }

    private var selection: Binding<Tab> {
        Binding(get: { tab }, set: { next in
            if next == .entry {
                if state.activeLedger?.archived == false { showEntry = true }
            } else { tab = next }
        })
    }

    var body: some View {
        if let failure = state.storageFailure {
            NavigationStack {
                List {
                    Section {
                        Label("账本需要恢复", systemImage: "externaldrive.badge.exclamationmark")
                            .font(.title2.bold())
                        Text(failure).foregroundStyle(.secondary)
                    }
                    Section {
                        Button("重新读取") { state.reloadFromDisk() }
                            .accessibilityIdentifier("recovery.retry")
                        NavigationLink("选择备份恢复") { DataManagementView() }
                    }
                }.navigationTitle("余记")
            }
        } else { mainTabs }
    }

    private var mainTabs: some View {
        TabView(selection: selection) {
            NavigationStack { LedgerHomeView(openStats: { tab = .stats }, openFeed: { tab = .feed }) }
                .tabItem { Label("账本", systemImage: "book.closed") }.tag(Tab.ledger)
            FeedView().tabItem { Label("流水", systemImage: "list.bullet") }.tag(Tab.feed)
            Color.clear.tabItem {
                Label { Text("记账") } icon: { Image(uiImage: entryIcon) }
                    .accessibilityIdentifier("root.newEntry")
            }.tag(Tab.entry)
            StatsView().tabItem { Label("统计", systemImage: "chart.bar") }.tag(Tab.stats)
            MeView().tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(Tab.me)
        }
        .tint(Design.primary(scheme))
        .environment(\.openLedgerEntry, { showEntry = true })
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["YUJI_UI_TEST_SESSION"] != nil { showEntry = true }
            if ProcessInfo.processInfo.environment["YUJI_STRESS_SESSION"] != nil,
               ProcessInfo.processInfo.environment["YUJI_TEST_STORE_MODE"] == nil {
                tab = .stats
                if ProcessInfo.processInfo.environment["YUJI_STRESS_PREVIEW"] == "1" { state.browsingPeriod = .year(2025) }
            }
            #endif
        }
        .sheet(isPresented: $showEntry) {
            EntryContainerView()
        }
    }

    /// Original rendering keeps the action accented while another destination stays selected.
    private var entryIcon: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 38, height: 28)).image { context in
            UIColor(Design.themeAccent(state.store.data.settings, scheme)).setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 38, height: 28), cornerRadius: 10).fill()
            let symbol = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))?
                .withTintColor(scheme == .dark ? .black : .white, renderingMode: .alwaysOriginal)
            symbol?.draw(in: CGRect(x: 10, y: 5, width: 18, height: 18))
        }.withRenderingMode(.alwaysOriginal)
    }
}

/// 录入容器：判断是否恢复草稿。
struct EntryContainerView: View {
    var onSaved: () -> Void = {}
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let ledger = state.activeLedger {
            let draft = state.store.draft(for: ledger.id)
            EntryView(ledger: ledger, draft: draft, onDone: { dismiss() }, onSaved: onSaved)
        } else {
            Text("请先创建账本").onAppear { dismiss() }
        }
    }
}

private struct OpenLedgerEntryKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}
extension EnvironmentValues {
    var openLedgerEntry: () -> Void {
        get { self[OpenLedgerEntryKey.self] }
        set { self[OpenLedgerEntryKey.self] = newValue }
    }
}
