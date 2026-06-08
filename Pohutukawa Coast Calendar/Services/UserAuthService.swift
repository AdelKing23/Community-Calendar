import Foundation
import Combine

enum UserAuthError: LocalizedError {
    case notConfigured
    case invalidResponse
    case signInFailed
    case signUpNeedsConfirmation

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Account services are not configured."
        case .invalidResponse:
            return "The account service returned an unexpected response."
        case .signInFailed:
            return "Sign in failed."
        case .signUpNeedsConfirmation:
            return "Check your email to confirm your account, then sign in."
        }
    }
}

struct UserSession: Hashable {
    let accessToken: String
    let refreshToken: String
    let userID: UUID
    let email: String?
    let expiresAt: Date?

    var shouldRefreshSoon: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date().addingTimeInterval(300)
    }
}

struct UserAuthService {
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    nonisolated init(session: URLSession = .shared) {
        self.session = session
    }

    func signIn(email: String, password: String) async throws -> UserSession {
        guard let authURL = SupabaseConfiguration.authURL?.appendingPathComponent("token"),
              var components = URLComponents(url: authURL, resolvingAgainstBaseURL: false),
              SupabaseConfiguration.isConfigured else {
            throw UserAuthError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "password")
        ]

        guard let url = components.url else {
            throw UserAuthError.notConfigured
        }

        let token = try await sendAuthRequest(
            url: url,
            body: UserPasswordAuthRequest(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password),
            failure: .signInFailed
        )

        guard let accessToken = token.accessToken,
              let refreshToken = token.refreshToken,
              let userID = token.user?.id else {
            throw UserAuthError.signInFailed
        }

        return UserSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userID: userID,
            email: token.user?.email,
            expiresAt: token.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
    }

    func signUp(email: String, password: String) async throws -> UserSession {
        guard let url = SupabaseConfiguration.authURL?.appendingPathComponent("signup"),
              SupabaseConfiguration.isConfigured else {
            throw UserAuthError.notConfigured
        }

        let token = try await sendAuthRequest(
            url: url,
            body: UserPasswordAuthRequest(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password),
            failure: .signInFailed
        )

        guard let accessToken = token.accessToken,
              let refreshToken = token.refreshToken,
              let userID = token.user?.id else {
            throw UserAuthError.signUpNeedsConfirmation
        }

        return UserSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userID: userID,
            email: token.user?.email,
            expiresAt: token.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
    }

    func refreshSession(refreshToken: String) async throws -> UserSession {
        guard let authURL = SupabaseConfiguration.authURL?.appendingPathComponent("token"),
              var components = URLComponents(url: authURL, resolvingAgainstBaseURL: false),
              SupabaseConfiguration.isConfigured else {
            throw UserAuthError.notConfigured
        }

        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]

        guard let url = components.url else {
            throw UserAuthError.notConfigured
        }

        let token = try await sendAuthRequest(
            url: url,
            body: UserRefreshAuthRequest(refreshToken: refreshToken),
            failure: .signInFailed
        )

        guard let accessToken = token.accessToken,
              let refreshToken = token.refreshToken,
              let userID = token.user?.id else {
            throw UserAuthError.signInFailed
        }

        return UserSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userID: userID,
            email: token.user?.email,
            expiresAt: token.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
    }

    private func sendAuthRequest<Body: Encodable>(
        url: URL,
        body: Body,
        failure: UserAuthError
    ) async throws -> SupabaseUserAuthResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UserAuthError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw failure
        }

        return try decoder.decode(SupabaseUserAuthResponse.self, from: data)
    }
}

@MainActor
final class UserSessionStore: ObservableObject {
    @Published private(set) var session: UserSession?
    @Published private(set) var isRestoring = false

    private let authService: UserAuthService
    private let keychain: SessionKeychainStore
    private let keychainAccount = "normal-user"

    init(authService: UserAuthService? = nil, keychain: SessionKeychainStore? = nil) {
        self.authService = authService ?? UserAuthService()
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
        let newSession = try await authService.signIn(email: email, password: password)
        session = newSession
        save(newSession)
    }

    func signUp(email: String, password: String) async throws {
        let newSession = try await authService.signUp(email: email, password: password)
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
            let refreshed = try await authService.refreshSession(refreshToken: session.refreshToken)
            self.session = refreshed
            save(refreshed)
        } catch {
            signOut()
        }
    }

    private func restoreSavedSession() {
        isRestoring = true

        do {
            if let saved = try keychain.load(StoredUserSession.self, for: keychainAccount)?.session {
                session = saved
                Task { await refreshIfNeeded() }
            }
        } catch {
            keychain.delete(account: keychainAccount)
        }

        isRestoring = false
    }

    private func save(_ session: UserSession) {
        try? keychain.save(StoredUserSession(session: session), for: keychainAccount)
    }
}

struct UserPasswordAuthRequest: Encodable {
    let email: String
    let password: String
}

struct UserRefreshAuthRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct SupabaseUserAuthResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let user: SupabaseAuthUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

private struct StoredUserSession: Codable {
    let accessToken: String
    let refreshToken: String
    let userID: UUID
    let email: String?
    let expiresAt: Date?

    init(session: UserSession) {
        self.accessToken = session.accessToken
        self.refreshToken = session.refreshToken
        self.userID = session.userID
        self.email = session.email
        self.expiresAt = session.expiresAt
    }

    var session: UserSession {
        UserSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userID: userID,
            email: email,
            expiresAt: expiresAt
        )
    }
}
