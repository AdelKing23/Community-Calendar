import Foundation

enum SupportAccessPolicy {
    private static let supportEmails: Set<String> = [
        "isaacwellis@hotmail.com"
    ]

    static func isSupportAccount(email: String?) -> Bool {
        guard let email else { return false }
        return supportEmails.contains(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
