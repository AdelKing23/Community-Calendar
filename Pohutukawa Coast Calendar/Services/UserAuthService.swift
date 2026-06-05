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
    let email: String?
    let expiresAt: Date?
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

        guard let accessToken = token.accessToken else {
            throw UserAuthError.signInFailed
        }

        return UserSession(
            accessToken: accessToken,
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

        guard let accessToken = token.accessToken else {
            throw UserAuthError.signUpNeedsConfirmation
        }

        return UserSession(
            accessToken: accessToken,
            email: token.user?.email,
            expiresAt: token.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
    }

    private func sendAuthRequest(
        url: URL,
        body: UserPasswordAuthRequest,
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

    private let authService: UserAuthService

    init(authService: UserAuthService = UserAuthService()) {
        self.authService = authService
    }

    var isSignedIn: Bool {
        session != nil
    }

    var email: String? {
        session?.email
    }

    func signIn(email: String, password: String) async throws {
        session = try await authService.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String) async throws {
        session = try await authService.signUp(email: email, password: password)
    }

    func signOut() {
        session = nil
    }
}

struct UserPasswordAuthRequest: Encodable {
    let email: String
    let password: String
}

struct SupabaseUserAuthResponse: Decodable {
    let accessToken: String?
    let expiresIn: Int?
    let user: SupabaseAuthUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case user
    }
}
