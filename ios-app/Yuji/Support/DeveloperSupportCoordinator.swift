import SwiftUI
import UIKit
import DeveloperSupportKit

@MainActor
final class DeveloperSupportCoordinator: ObservableObject {
    enum Presentation: String, Identifiable {
        case invitation, support
        var id: String { rawValue }
    }
    static let entryTitle = "好用，请开发者喝杯☕吧"
    static let tiers = [
        SupportTier(id: "com.yuji.app.support.encourage", title: "小小鼓励"),
        SupportTier(id: "com.yuji.app.support.coffee", title: "一杯咖啡"),
        SupportTier(id: "com.yuji.app.support.generous", title: "加倍支持")
    ]
    @Published var presentation: Presentation?
    let model: SupportModel
    let invitation: RecordSupportInvitation
    private weak var state: AppState?
    private var active = false
    private var invitationTask: Task<Void, Never>?
    private var taskID: UUID?
    private var openSupportAfterDismiss = false
    private var needsThanks = false
    private var recoveryTask: Task<Void, Never>?

    init(client: any SupportClient, directory: URL) {
        model = SupportModel(client: client, directory: directory, scope: "com.yuji.app/developer-support")
        invitation = RecordSupportInvitation(directory: directory)
    }
    deinit { invitationTask?.cancel(); recoveryTask?.cancel() }

    func attach(to state: AppState) {
        self.state = state
        state.onRecordCreated = { [weak self] id in
            self?.invitation.recordCreated(id.raw)
            self?.scheduleInvitation()
        }
    }

    func setActive(_ value: Bool) {
        active = value
        if value {
            showThanksIfReady()
            recoveryTask?.cancel()
            recoveryTask = Task { [weak self] in await self?.model.checkStatus() }
            scheduleInvitation()
        }
        else { cancelPresentationTask() }
    }

    func presentManually() {
        guard presentation == nil else { return }
        cancelPresentationTask()
        openSupportAfterDismiss = false
        presentation = .support
    }

    func acceptInvitation() {
        openSupportAfterDismiss = true
        presentation = nil
    }

    func didDismiss() {
        showThanksIfReady()
        scheduleInvitation()
    }

    /// Only the current user-initiated flow may dismiss this presentation.
    /// Historical receipt recovery stays in the payment module.
    /// Dismiss first so the confirmation is visible on the page underneath.
    func supportCompleted(_ receipt: SupportReceipt) {
        guard !receipt.revoked else { return }
        needsThanks = true
        openSupportAfterDismiss = false
        if presentation == .support { presentation = nil }
        else { showThanksIfReady() }
    }

    private func showThanksIfReady() {
        guard needsThanks, active, presentation == nil, let state else { return }
        needsThanks = false
        state.showSupportThanks()
    }

    private func scheduleInvitation() {
        guard active, openSupportAfterDismiss || invitation.eligible,
              presentation == nil, invitationTask == nil else { return }
        let id = UUID()
        taskID = id
        invitationTask = Task { [weak self] in
            guard let self else { return }
            // A cancelled older task must not clear a replacement started after foregrounding.
            defer { if taskID == id { invitationTask = nil; taskID = nil } }
            if !openSupportAfterDismiss {
                await model.checkStatus()
                guard !Task.isCancelled, active, taskID == id else { return }
                if model.hasSupported { invitation.consume(); return }
                await model.loadOffers()
                guard !Task.isCancelled, model.mayInvite else { return }
            }
            while !Task.isCancelled && active && taskID == id {
                if canPresent {
                    if openSupportAfterDismiss {
                        openSupportAfterDismiss = false
                        presentation = .support
                        return
                    }
                    guard invitation.consume() else { return }
                    presentation = .invitation
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func cancelPresentationTask() {
        invitationTask?.cancel()
        invitationTask = nil
        taskID = nil
    }

    /// Save events can happen inside entry, refund or transfer sheets. Wait for the real
    /// presentation and keyboard to leave rather than stacking another modal over them.
    private var canPresent: Bool {
        guard active, presentation == nil, state?.storageFailure == nil,
              state?.alertError == nil, state?.isSaving == false,
              CloudInvitationCenter.shared.pending == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let root = window.rootViewController else { return false }
        return root.presentedViewController == nil && !root.isBeingPresented && !root.isBeingDismissed
            && root.transitionCoordinator == nil && window.keyboardLayoutGuide.layoutFrame.height < 100
    }

    static func live() -> DeveloperSupportCoordinator {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        for key in ["YUJI_STRESS_SESSION", "YUJI_UI_TEST_SESSION"] {
            if let value = environment[key], UUID(uuidString: value) == nil { fatalError("Invalid support test session") }
        }
        if let session = ["YUJI_STRESS_SESSION", "YUJI_UI_TEST_SESSION"].compactMap({ environment[$0] }).first {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("yuji-support-\(session)", isDirectory: true)
            let client: any SupportClient = environment["YUJI_TEST_SUPPORT_MODE"] == "storekit"
                ? StoreKitSupportClient(tiers: tiers) : IsolatedSupportClient(mode: environment["YUJI_TEST_SUPPORT_MODE"])
            let coordinator = DeveloperSupportCoordinator(client: client, directory: directory)
            if environment["YUJI_TEST_SUPPORT_RECORDS"] == "99", coordinator.invitation.count == 0 {
                for index in 0..<99 { coordinator.invitation.recordCreated("isolated-seed-\(index)") }
            }
            return coordinator
        }
        #endif
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YujiDeveloperSupport", isDirectory: true)
        return DeveloperSupportCoordinator(client: StoreKitSupportClient(tiers: tiers), directory: directory)
    }
}

#if DEBUG
/// Available only in a UUID-isolated test. Ordinary regressions never contact payment services.
@MainActor
private final class IsolatedSupportClient: SupportClient {
    let updates = AsyncStream<SupportReceipt> { $0.finish() }
    private let mode: String?
    init(mode: String?) { self.mode = mode }
    func offers() async throws -> [SupportOffer] {
        guard ["preview", "uncertain", "cancelled", "pending"].contains(mode) else { return [] }
        return zip(DeveloperSupportCoordinator.tiers, ["¥6.00", "¥18.00", "¥30.00"]).map {
            SupportOffer(id: $0.0.id, title: $0.0.title, displayPrice: $0.1)
        }
    }
    func purchase(_ productID: String) async throws -> SupportPurchaseResult {
        if mode == "cancelled" { return .cancelled }
        if mode == "pending" { return .pending }
        throw CocoaError(.fileReadUnknown)
    }
    func recover() async throws -> [SupportReceipt] { [] }
    func finish(_ receipt: SupportReceipt) async {}
}
#endif
