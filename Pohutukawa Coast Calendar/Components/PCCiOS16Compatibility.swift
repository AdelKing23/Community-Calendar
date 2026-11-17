import SwiftUI

// iOS 16 support (t242): small shims for SwiftUI APIs that are iOS 17+ (or 16.4+).
// On iOS 17+ each shim calls the same API the app used before, so behaviour there is unchanged.

extension View {
    /// `onChange(of:)` with (oldValue, newValue). Uses the iOS 17 API when available.
    func pccOnChange<V: Equatable>(of value: V, _ action: @escaping (V, V) -> Void) -> some View {
        modifier(PCCOnChangeModifier(value: value, action: action))
    }

    /// `onChange(of:)` with no parameters. Uses the iOS 17 API when available.
    func pccOnChange<V: Equatable>(of value: V, _ action: @escaping () -> Void) -> some View {
        modifier(PCCOnChangeModifier(value: value, action: { _, _ in action() }))
    }

    /// `scrollBounceBehavior(.basedOnSize)` on iOS 16.4+, no-op before.
    func pccScrollBounceBasedOnSize() -> some View {
        modifier(PCCScrollBounceBasedOnSizeModifier())
    }
}

private struct PCCOnChangeModifier<V: Equatable>: ViewModifier {
    let value: V
    let action: (V, V) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.onChange(of: value) { oldValue, newValue in
                action(oldValue, newValue)
            }
        } else {
            // The capture list holds the value from the render that installed this closure (the old value).
            content.onChange(of: value) { [value] newValue in
                action(value, newValue)
            }
        }
    }
}

private struct PCCScrollBounceBasedOnSizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.scrollBounceBehavior(.basedOnSize)
        } else {
            content
        }
    }
}

extension ToolbarItemPlacement {
    /// `.topBarTrailing` on iOS 17+, `.navigationBarTrailing` (same position) before.
    static var pccTopBarTrailing: ToolbarItemPlacement {
        if #available(iOS 17.0, *) {
            return .topBarTrailing
        }
        return .navigationBarTrailing
    }

    /// `.topBarLeading` on iOS 17+, `.navigationBarLeading` (same position) before.
    static var pccTopBarLeading: ToolbarItemPlacement {
        if #available(iOS 17.0, *) {
            return .topBarLeading
        }
        return .navigationBarLeading
    }
}
