import SwiftUI
import YujiCore

@main
struct YujiApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(colorScheme)
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
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
        }
    }

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
                    .foregroundColor(Color(red: 0x9D/255.0, green: 0xCA/255.0, blue: 0xB0/255.0))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Capsule().fill(Color.black.opacity(0.82)))
    }
}
