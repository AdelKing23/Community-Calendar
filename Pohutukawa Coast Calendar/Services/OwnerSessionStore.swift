import Foundation
import Combine

@MainActor
final class OwnerSessionStore: ObservableObject {
    @Published private(set) var session: OwnerSession?
    @Published private(set) var isRestoring = false

    private let authService: any OwnerAuthenticating
    private let keychain: SessionKeychainStore
    private let keychainAccount = "owner-support"

    init(
        authService: (any OwnerAuthenticating)? = nil,
        keychain: SessionKeychainStore? = nil
    ) {
        self.authService = authService ?? SupabaseEventService()
        self.keychain = keychain ?? SessionKeychainStore()
        restoreSavedSession()
    }

    var isSignedIn: Bool {
        session != nil
    }

    var email: String? {
        session?.email
    }

    func signIn(email: String, password: String) async throws {
        let newSession = try await authService.signInOwner(email: email, password: password)
        session = newSession
        save(newSession)
    }

    func signOut() {
        session = nil
        keychain.delete(account: keychainAccount)
    }

    func refreshIfNeeded() async {
        guard let session, session.shouldRefreshSoon else { return }

        do {
            let refreshed = try await authService.refreshOwnerSession(refreshToken: session.refreshToken)
            self.session = refreshed
            save(refreshed)
        } catch {
            signOut()
        }
    }

    private func restoreSavedSession() {
        isRestoring = true

        do {
            if let saved = try keychain.load(StoredOwnerSession.self, for: keychainAccount)?.session {
                session = saved
                Task { await refreshIfNeeded() }
            }
        } catch {
            keychain.delete(account: keychainAccount)
        }

        isRestoring = false
    }

    private func save(_ session: OwnerSession) {
        try? keychain.save(StoredOwnerSession(session: session), for: keychainAccount)
    }
}

private struct StoredOwnerSession: Codable {
    let accessToken: String
    let refreshToken: String
    let email: String?
    let expiresAt: Date?

    init(session: OwnerSession) {
        self.accessToken = session.accessToken
        self.refreshToken = session.refreshToken
        self.email = session.email
        self.expiresAt = session.expiresAt
    }

    var session: OwnerSession {
        OwnerSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            email: email,
            expiresAt: expiresAt
        )
    }
}
