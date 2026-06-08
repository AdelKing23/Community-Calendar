import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum PCCKeyboardSpacing {
    static let standardTopPadding: CGFloat = 76
    static let standardBottomPadding: CGFloat = 210
    static let homeBottomPadding: CGFloat = 260
    static let formBottomPadding: CGFloat = 300
    static let standardBottomInset: CGFloat = 132
    static let formBottomInset: CGFloat = 168
}

extension View {
    func pccTracksKeyboardVisibility(_ isVisible: Binding<Bool>) -> some View {
        modifier(PCCKeyboardVisibilityModifier(isVisible: isVisible))
    }

    func pccDismissesKeyboardOnTap(_ onDismiss: @escaping () -> Void = {}) -> some View {
        modifier(PCCDismissKeyboardOnTapModifier(onDismiss: onDismiss))
    }

    func pccScrollableKeyboardDismiss() -> some View {
        scrollDismissesKeyboard(.interactively)
    }

    func pccBottomKeyboardInset(_ height: CGFloat = PCCKeyboardSpacing.standardBottomInset) -> some View {
        safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: height)
        }
    }

    func pccKeyboardDoneToolbar(_ action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("Done", action: action)
                    .font(.headline.weight(.bold))
            }
        }
    }
}

private struct PCCKeyboardVisibilityModifier: ViewModifier {
    @Binding var isVisible: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                isVisible = false
            }
    }
}

private struct PCCDismissKeyboardOnTapModifier: ViewModifier {
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    onDismiss()
                    UIApplication.pccDismissKeyboard()
                }
            )
    }
}

#if canImport(UIKit)
extension UIApplication {
    static func pccDismissKeyboard() {
        shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif
