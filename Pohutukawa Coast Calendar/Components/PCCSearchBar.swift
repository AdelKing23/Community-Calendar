import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PCCSearchBar: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PCCTheme.leafGreen.opacity(0.65))

            TextField("Search event, date, town or type", text: $text)
                .focused($isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(PCCTheme.ink)
                .tint(PCCTheme.pohutukawaOrange)
                .submitLabel(.search)
                .onSubmit {
                    isFocused = false
                }

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(PCCTheme.leafGreen.opacity(0.45))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(PCCTheme.leafGreen.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 14, x: 0, y: 8)
    }
}

#if canImport(UIKit)
extension UIApplication {
    static func pccDismissKeyboard() {
        shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif
