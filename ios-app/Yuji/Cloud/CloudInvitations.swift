import CloudKit
import SwiftUI
import UIKit
import YujiCore

@MainActor final class CloudInvitationCenter: ObservableObject {
    static let shared = CloudInvitationCenter()
    @Published var pending: CKShare.Metadata?
    @Published var error: String?
    func receive(_ metadata: CKShare.Metadata) { pending = metadata }
}

final class YujiApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = YujiCloudSceneDelegate.self
        return configuration
    }
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        CloudInvitationCenter.shared.receive(metadata)
    }
}
final class YujiCloudSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        if let metadata = options.cloudKitShareMetadata { CloudInvitationCenter.shared.receive(metadata) }
    }
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        CloudInvitationCenter.shared.receive(metadata)
    }
}

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let title: String
    let completion: (String?) -> Void
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var scheme
    func makeCoordinator() -> Coordinator { Coordinator(title: title, completion: completion) }
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowPrivate, .allowReadOnly, .allowReadWrite]
        controller.view.tintColor = UIColor(Design.themeAccent(state.store.data.settings, scheme))
        return controller
    }
    func updateUIViewController(_ controller: UICloudSharingController, context: Context) { }
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let title: String; let completion: (String?) -> Void
        init(title: String, completion: @escaping (String?) -> Void) { self.title = title; self.completion = completion }
        func itemTitle(for csc: UICloudSharingController) -> String? { title }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) { completion("共享设置未保存，请重试。") }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { completion(nil) }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { completion(nil) }
    }
}

struct CloudInvitationView: View {
    let metadata: CKShare.Metadata
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var accepting = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("加入共同账本", systemImage: "person.2").font(.title2.weight(.semibold))
                    Text(metadata.share[CKShare.SystemFieldKey.title] as? String ?? "共享账本").font(.headline)
                    Text("加入后可查看账本的账户、分类、流水、备注和预算。能否记账由拥有者设置的权限决定。")
                }
                Section {
                    Text("仅加入这一个账本。你的其他账本和个人草稿不会共享。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let message { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("cloud.accept.error") }
                }
            }.navigationTitle("账本邀请").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("稍后") { dismiss() }.disabled(accepting) } }
                .safeAreaInset(edge: .bottom) {
                    Button(accepting ? "正在加入…" : "接受邀请") { Task { await accept() } }
                        .buttonStyle(SolidActionStyle()).disabled(accepting)
                        .accessibilityIdentifier("cloud.accept")
                        .padding(20).background(Color(.systemBackground))
                }
        }
        .modifier(CleanSheetSurface())
        .presentationDetents([.fraction(0.7), .large]).presentationDragIndicator(.visible)
        .interactiveDismissDisabled(accepting)
    }
    private func accept() async {
        guard let transport = state.cloudTransport as? CloudKitTransport else { message = CloudSyncError.unavailable.message; return }
        accepting = true; defer { accepting = false }
        do {
            await state.refreshCloudAccount()
            guard state.cloudAccountReady, let account = state.cloudAccountID else { message = state.cloudStatus; return }
            let epoch = state.cloudEpoch
            try await transport.accept(metadata)
            guard state.cloudEpoch == epoch, state.cloudAccountID == account else { message = "iCloud 账号已变化，请重新打开邀请。"; return }
            // A foreground refresh may already be running. Wait for its lane;
            // an early no-op must not make a stale cached book look downloaded.
            for _ in 0..<300 {
                if !state.cloudBusy { break }
                try await Task.sleep(nanoseconds: 100_000_000)
                guard state.cloudEpoch == epoch, state.cloudAccountID == account else { message = "iCloud 账号已变化，请重新打开邀请。"; return }
            }
            guard !state.cloudBusy else { message = "邀请已接受，同步仍在进行。请稍后重试。"; return }
            let zone = metadata.share.recordID.zoneID
            let existing = state.currentCloudLinks.first {
                $0.address.scope == .shared && $0.address.zoneName == zone.zoneName && $0.address.ownerName == zone.ownerName
            }
            await state.synchronizeCloud(forceLedgerID: existing?.cached.ledger.id)
            guard state.cloudEpoch == epoch, state.cloudAccountID == account else { message = "iCloud 账号已变化，请重新打开邀请。"; return }
            guard let link = state.currentCloudLinks.first(where: { $0.address.scope == .shared && $0.address.zoneName == zone.zoneName && $0.address.ownerName == zone.ownerName }) else {
                message = "邀请已接受，账本尚未下载完成。请联网后重试。"; return
            }
            guard link.lastSync != nil, link.issue == nil, link.incoming == nil else {
                message = "邀请已接受，账本同步尚未完成。" + (link.issue ?? "请稍后重试。")
                return
            }
            guard state.switchLedger(link.cached.ledger.id) else { message = state.alertError ?? "账本定位未保存，请重试。"; return }
            dismiss()
        } catch { message = CloudLedgerMerge.describe(error) }
    }
}
