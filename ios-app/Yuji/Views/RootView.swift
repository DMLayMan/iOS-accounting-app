import SwiftUI
import YujiCore

struct RootView: View {
    @EnvironmentObject var state: AppState
    @State private var tab: Tab = .ledger
    @State private var showEntry = false

    enum Tab { case ledger, feed, stats, me }

    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                LedgerHomeView()
                    .tabItem { Label("账本", systemImage: "book.closed") }
                    .tag(Tab.ledger)

                FeedView()
                    .tabItem { Label("流水", systemImage: "list.bullet") }
                    .tag(Tab.feed)

                StatsView()
                    .tabItem { Label("统计", systemImage: "chart.bar") }
                    .tag(Tab.stats)

                MeView()
                    .tabItem { Label("我的", systemImage: "person.crop.circle") }
                    .tag(Tab.me)
            }
            .tint(Design.sage)

            // 中央 ＋：手指位置固定；有草稿时恢复草稿
            VStack {
                Spacer()
                Button {
                    showEntry = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Design.sage))
                        .shadow(color: Design.sage.opacity(0.35), radius: 8, y: 3)
                }
                .padding(.bottom, 14)
                .accessibilityLabel("记一笔")
            }
            .allowsHitTesting(true)
        }
        .sheet(isPresented: $showEntry) {
            EntryContainerView()
        }
    }
}

/// 录入容器：判断是否恢复草稿。
struct EntryContainerView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let ledger = state.activeLedger {
            let draft = state.store.draft(for: ledger.id)
            EntryView(ledger: ledger, draft: draft, onDone: { dismiss() })
        } else {
            Text("请先创建账本").onAppear { dismiss() }
        }
    }
}
