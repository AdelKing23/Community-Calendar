import SwiftUI
import UIKit

/// t278/t279: one shared way to confirm that a tap changed something.
/// Use it only for actions that change something (set, add, save, vote, belong, submit).
/// Pure navigation keeps the normal button bounce.
@MainActor
enum PCCFeedback {
    enum Style { case success, info, error }

    /// Light haptic for a toggle or selection that changed.
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Success haptic plus a short toast.
    static func success(_ message: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        PCCToastPresenter.shared.show(message, style: .success)
    }

    /// Light haptic plus a short toast, for a change that is not a "win" (e.g. removed).
    static func info(_ message: String) {
        tap()
        PCCToastPresenter.shared.show(message, style: .info)
    }

    /// Warning haptic plus a toast, for failures and permission problems.
    static func error(_ message: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        PCCToastPresenter.shared.show(message, style: .error)
    }
}

/// Shows the toast in its own pass-through window so it also appears above sheets.
@MainActor
final class PCCToastPresenter {
    static let shared = PCCToastPresenter()
    private var window: UIWindow?
    private var hideWork: DispatchWorkItem?
    private var visibleFor: TimeInterval { 2.2 }

    func show(_ message: String, style: PCCFeedback.Style) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let host = UIHostingController(rootView: PCCToastView(message: message, style: style))
        host.view.backgroundColor = .clear
        let win = window ?? PCCPassThroughWindow(windowScene: scene)
        win.windowLevel = .alert + 1
        win.backgroundColor = .clear
        win.rootViewController = host
        win.isHidden = false
        window = win
        UIAccessibility.post(notification: .announcement, argument: message)

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.window?.isHidden = true
            self?.window?.rootViewController = nil
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + visibleFor, execute: work)
    }
}

private final class PCCPassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === rootViewController?.view ? nil : hit
    }
}

struct PCCToastView: View {
    let message: String
    let style: PCCFeedback.Style
    @State private var shown = false

    var body: some View {
        VStack {
            Spacer()
            Label(message, systemImage: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(background, in: Capsule(style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
                .padding(.horizontal, 24)
                .padding(.bottom, 104)
                .offset(y: shown ? 0 : 24)
                .opacity(shown ? 1 : 0)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { shown = true } }
    }

    private var icon: String {
        switch style {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    private var background: Color {
        switch style {
        case .success: return PCCTheme.leafGreen
        case .info: return PCCTheme.ink
        case .error: return PCCTheme.pohutukawaRed
        }
    }
}
