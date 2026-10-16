import Foundation
import Combine

enum UserAuthError: LocalizedError {
    case notConfigured
    case invalidResponse
    case signInFailed
    case requestFailed(Int, String?)
    case signUpNeedsConfirmation
    case verificationEmailFailed
    case passwordResetFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Account services are not configured."
        case .invalidResponse:
            return "The account service returned an unexpected response."
        case .signInFailed:
            return "Sign in failed. Check your email and password, then try again."
        case .requestFailed(let statusCode, let message):
            return SupabaseServiceError.requestFailed(statusCode, message).errorDescription
        case .signUpNeedsConfirmation:
            return "Check your email to confirm your account, then sign in."
        case .verificationEmailFailed:
            return "Verification email could not be sent. Please check the address and try again."
        case .passwordResetFailed:
            return "Password reset email could not be sent. Please check the address and try again."
        }
    }
}


enum PCCPersonalGreeting {
    static func line(name: String?, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let hour = calendar.component(.hour, from: now)
        let hello: String
        switch hour {
        case 5..<12: hello = "Good morning"
        case 12..<17: hello = "Good afternoon"
        default: hello = "Good evening"
        }
        return "\(hello) \(name)"
    }
}

struct UserSession: Hashable {
    let accessToken: String
    let refreshToken: String
    let userID: UUID
    let email: String?
    let isEmailVerified: Bool
    let fullName: String?
    let expiresAt: Date?

    var greetingName: String? {
        let raw = (fullName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return raw.split { $0.isWhitespace }.first.map(String.init)
    }

    func updatingFullName(_ name: String?) -> UserSession {
        UserSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userID: userID,
            email: email,
            isEmailVerified: isEmailVerified,
            fullName: name,
            expiresAt: expiresAt
        )
    }

    var shouldRefreshSoon: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date().addingTimeInterval(300)
    }
}

struct UserAccountContext: Hashable, Sendable {
    let userID: UUID?
    let generation: UInt64
}

protocol UserAuthenticating {
    func signIn(email: String, password: String) async throws -> UserSession
    func signUp(email: String, password: String) async throws -> UserSession
    func signUp(email: String, password: String, fullName: String) async throws -> UserSession
    func refreshSession(refreshToken: String) async throws -> UserSession
    func updateFullName(accessToken: String, fullName: String) async throws
    func resendVerificationEmail(email: String) async throws
    func sendPasswordResetEmail(email: String) async throws
}

struct UserAuthService: UserAuthenticating {
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
            isEmailVerified: token.user?.isEmailVerified ?? false,
            fullName: token.user?.fullName,
            expiresAt: token.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
    }

    func signUp(email: String, password: String) async throws -> UserSession {
        try await signUp(email: email, password: password, fullName: "")
    }

    func signUp(email: String, password: String, fullName: String = "") async throws -> UserSession {
        guard let url = SupabaseConfiguration.authURL?.appendingPathComponent("signup"),
              SupabaseConfiguration.isConfigured else {
            throw UserAuthError.notConfigured
        }

        let token = try await sendAuthRequest(
            url: url,
            body: UserPasswordAuthRequest(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                fullName: fullName
            ),
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
            isEmailVerified: token.user?.isEmailVerified ?? false,
            fullName: token.user?.fullName,
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
            isEmailVerified: token.user?.isEmailVerified ?? false,
            fullName: token.user?.fullName,
            expiresAt: token.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
        )
    }


    func updateFullName(accessToken: String, fullName: String) async throws {
        guard let url = SupabaseConfiguration.authURL?.appendingPathComponent("user"),
              SupabaseConfiguration.isConfigured else {
            throw UserAuthError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(UserFullNameUpdateRequest(data: ["full_name": fullName]))

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw UserAuthError.invalidResponse
        }
    }

    func resendVerificationEmail(email: String) async throws {
        guard let url = SupabaseConfiguration.authURL?.appendingPathComponent("resend"),
              SupabaseConfiguration.isConfigured else {
            throw UserAuthError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(UserResendAuthRequest(type: "signup", email: email.trimmingCharacters(in: .whitespacesAndNewlines)))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 400
            throw UserAuthError.requestFailed(statusCode, String(data: data, encoding: .utf8))
        }
    }

    func sendPasswordResetEmail(email: String) async throws {
        guard let url = SupabaseConfiguration.authURL?.appendingPathComponent("recover"),
              SupabaseConfiguration.isConfigured else {
            throw UserAuthError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(UserPasswordResetRequest(email: email.trimmingCharacters(in: .whitespacesAndNewlines)))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 400
            throw UserAuthError.requestFailed(statusCode, String(data: data, encoding: .utf8))
        }
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
            throw UserAuthError.requestFailed(httpResponse.statusCode, String(data: data, encoding: .utf8))
        }

        return try decoder.decode(SupabaseUserAuthResponse.self, from: data)
    }
}

@MainActor
final class UserSessionStore: ObservableObject {
    @Published private(set) var session: UserSession?
    @Published private(set) var isRestoring = false
    @Published private(set) var accountGeneration: UInt64 = 0

    private let authService: any UserAuthenticating
    private let keychain: SessionKeychainStore
    private let keychainAccount = "normal-user"
    private let persistsSession: Bool

    init(
        authService: (any UserAuthenticating)? = nil,
        keychain: SessionKeychainStore? = nil,
        persistsSession: Bool = true
    ) {
        self.authService = authService ?? UserAuthService()
        self.keychain = keychain ?? SessionKeychainStore()
        self.persistsSession = persistsSession
        if persistsSession {
            restoreSavedSession()
        }
    }

    var isSignedIn: Bool {
        session != nil
    }

    var email: String? {
        session?.email
    }

    var isEmailVerified: Bool {
        session?.isEmailVerified == true
    }

    var accountContext: UserAccountContext {
        UserAccountContext(userID: session?.userID, generation: accountGeneration)
    }

    func captureAccountContext() -> UserAccountContext {
        accountContext
    }

    func isCurrent(_ context: UserAccountContext) -> Bool {
        accountContext == context
    }

    func signIn(email: String, password: String) async throws {
        let requestContext = captureAccountContext()
        let newSession = try await authService.signIn(email: email, password: password)
        try Task.checkCancellation()
        guard isCurrent(requestContext) else { throw CancellationError() }
        replaceSession(with: newSession)
    }

    func signUp(email: String, password: String, fullName: String = "") async throws {
        let requestContext = captureAccountContext()
        let newSession = try await authService.signUp(email: email, password: password, fullName: fullName)
        try Task.checkCancellation()
        guard isCurrent(requestContext) else { throw CancellationError() }
        replaceSession(with: newSession)
    }

    func signOut() {
        replaceSession(with: nil)
    }

    func updateFullName(_ raw: String) async throws {
        guard let session else { throw UserAuthError.signInFailed }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { throw UserAuthError.invalidResponse }
        try await authService.updateFullName(accessToken: session.accessToken, fullName: trimmed)
        replaceSession(with: session.updatingFullName(trimmed))
    }

    func refreshIfNeeded() async {
        guard let session, session.shouldRefreshSoon else { return }
        let requestContext = captureAccountContext()

        do {
            let refreshed = try await authService.refreshSession(refreshToken: session.refreshToken)
            guard !Task.isCancelled else { return }
            guard isCurrent(requestContext) else { return }
            guard refreshed.userID == requestContext.userID else {
                throw UserAuthError.invalidResponse
            }
            replaceSession(with: refreshed)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard isCurrent(requestContext) else { return }
            signOut()
        }
    }

    func refreshNow() async throws {
        guard let session else { return }
        let requestContext = captureAccountContext()
        let refreshed = try await authService.refreshSession(refreshToken: session.refreshToken)
        try Task.checkCancellation()
        guard isCurrent(requestContext) else { throw CancellationError() }
        guard refreshed.userID == requestContext.userID else {
            throw UserAuthError.invalidResponse
        }
        replaceSession(with: refreshed)
    }

    func resendVerificationEmail() async throws {
        guard let email else { return }
        try await authService.resendVerificationEmail(email: email)
    }

    func sendPasswordResetEmail(email: String) async throws {
        try await authService.sendPasswordResetEmail(email: email)
    }

    private func restoreSavedSession() {
        isRestoring = true

        do {
            if let saved = try keychain.load(StoredUserSession.self, for: keychainAccount)?.session {
                replaceSession(with: saved, updateKeychain: false)
                Task { await refreshIfNeeded() }
            }
        } catch {
            keychain.delete(account: keychainAccount)
        }

        isRestoring = false
    }

    private func replaceSession(with newSession: UserSession?, updateKeychain: Bool = true) {
        accountGeneration += 1
        session = newSession

        guard updateKeychain, persistsSession else { return }
        if let newSession {
            save(newSession)
        } else {
            keychain.delete(account: keychainAccount)
        }
    }

    private func save(_ session: UserSession) {
        guard persistsSession else { return }
        try? keychain.save(StoredUserSession(session: session), for: keychainAccount)
    }
}

struct AccountProfile: Codable, Equatable {
    enum ContactVisibility: String, CaseIterable, Codable, Identifiable {
        case anonymous
        case nameAndEmail
        case publicProfile

        var id: String { rawValue }

        var title: String {
            switch self {
            case .anonymous: return "Anonymous"
            case .nameAndEmail: return "Name + email"
            case .publicProfile: return "Public profile"
            }
        }

        var detail: String {
            switch self {
            case .anonymous:
                return "Do not prefill public contact details on new listings."
            case .nameAndEmail:
                return "Prefill a simple public contact name and email."
            case .publicProfile:
                return "Use your organiser details as the public listing contact."
            }
        }
    }

    var displayName: String
    var publicRole: String
    var organisationName: String
    var phone: String
    var website: String
    var preferredContactEmail: String
    var contactVisibility: ContactVisibility

    static let empty = AccountProfile(
        displayName: "",
        publicRole: "",
        organisationName: "",
        phone: "",
        website: "",
        preferredContactEmail: "",
        contactVisibility: .nameAndEmail
    )

    init(
        displayName: String,
        publicRole: String,
        organisationName: String,
        phone: String,
        website: String,
        preferredContactEmail: String,
        contactVisibility: ContactVisibility = .nameAndEmail
    ) {
        self.displayName = displayName
        self.publicRole = publicRole
        self.organisationName = organisationName
        self.phone = phone
        self.website = website
        self.preferredContactEmail = preferredContactEmail
        self.contactVisibility = contactVisibility
    }

    enum CodingKeys: String, CodingKey {
        case displayName
        case publicRole
        case organisationName
        case phone
        case website
        case preferredContactEmail
        case contactVisibility
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        publicRole = try container.decodeIfPresent(String.self, forKey: .publicRole) ?? ""
        organisationName = try container.decodeIfPresent(String.self, forKey: .organisationName) ?? ""
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        website = try container.decodeIfPresent(String.self, forKey: .website) ?? ""
        preferredContactEmail = try container.decodeIfPresent(String.self, forKey: .preferredContactEmail) ?? ""
        contactVisibility = try container.decodeIfPresent(ContactVisibility.self, forKey: .contactVisibility) ?? .nameAndEmail
    }

    var hasPublicIdentity: Bool {
        contactVisibility != .anonymous
            && (!displayName.trimmed.isEmpty || !organisationName.trimmed.isEmpty)
    }

    var publicDisplayName: String {
        let name = displayName.trimmed
        let organisation = organisationName.trimmed

        if !name.isEmpty, !organisation.isEmpty {
            return "\(name), \(organisation)"
        }

        if !name.isEmpty {
            return name
        }

        if !organisation.isEmpty {
            return organisation
        }

        return "Local organiser"
    }

    var publicByline: String {
        let role = publicRole.trimmed
        let organisation = organisationName.trimmed

        switch (role.isEmpty, organisation.isEmpty) {
        case (false, false):
            return "\(role), \(organisation)"
        case (false, true):
            return role
        case (true, false):
            return organisation
        case (true, true):
            return "Community listing contact"
        }
    }

    var listingContactName: String {
        guard contactVisibility != .anonymous else { return "" }

        let name = displayName.trimmed
        let role = publicRole.trimmed
        let organisation = organisationName.trimmed

        if contactVisibility == .nameAndEmail {
            if !name.isEmpty { return name }
            if !organisation.isEmpty { return organisation }
            return ""
        }

        if !name.isEmpty, !role.isEmpty, !organisation.isEmpty {
            return "\(name), \(role), \(organisation)"
        }

        if !name.isEmpty, !organisation.isEmpty {
            return "\(name), \(organisation)"
        }

        return publicDisplayName
    }

    var listingContactEmail: String {
        guard contactVisibility != .anonymous else { return "" }
        return preferredContactEmail.trimmed
    }
}

@MainActor
final class AccountProfileStore: ObservableObject {
    @Published private(set) var profile: AccountProfile

    private let defaults: UserDefaults
    private let legacyKey = "communityCalendar.accountProfile"
    private var activeUserID: UUID?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.profile = .empty
        defaults.removeObject(forKey: legacyKey)
    }

    func bind(to userID: UUID?) {
        guard activeUserID != userID else { return }
        activeUserID = userID

        guard let userID else {
            profile = .empty
            return
        }

        if let data = defaults.data(forKey: key(for: userID)),
           let saved = try? decoder.decode(AccountProfile.self, from: data) {
            profile = saved
        } else {
            profile = .empty
        }
    }

    func save(_ newProfile: AccountProfile) {
        guard let activeUserID else { return }

        let normalizedProfile = AccountProfile(
            displayName: newProfile.displayName.trimmed,
            publicRole: newProfile.publicRole.trimmed,
            organisationName: newProfile.organisationName.trimmed,
            phone: newProfile.phone.trimmed,
            website: newProfile.website.trimmed,
            preferredContactEmail: newProfile.preferredContactEmail.trimmed,
            contactVisibility: newProfile.contactVisibility
        )

        profile = normalizedProfile
        if let data = try? encoder.encode(normalizedProfile) {
            defaults.set(data, forKey: key(for: activeUserID))
        }
    }

    func reset() {
        profile = .empty
        if let activeUserID {
            defaults.removeObject(forKey: key(for: activeUserID))
        }
        defaults.removeObject(forKey: legacyKey)
    }

    private func key(for userID: UUID) -> String {
        "communityCalendar.accountProfile.\(userID.uuidString.lowercased())"
    }
}

struct UserFullNameUpdateRequest: Encodable {
    let data: [String: String]
}

struct UserPasswordAuthRequest: Encodable {
    let email: String
    let password: String
    let data: [String: String]?

    init(email: String, password: String, fullName: String? = nil) {
        self.email = email
        self.password = password
        let trimmed = (fullName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.data = trimmed.isEmpty ? nil : ["full_name": trimmed]
    }
}

struct UserRefreshAuthRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

struct UserResendAuthRequest: Encodable {
    let type: String
    let email: String
}

struct UserPasswordResetRequest: Encodable {
    let email: String
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
    let isEmailVerified: Bool
    let fullName: String?
    let expiresAt: Date?

    init(session: UserSession) {
        self.accessToken = session.accessToken
        self.refreshToken = session.refreshToken
        self.userID = session.userID
        self.email = session.email
        self.isEmailVerified = session.isEmailVerified
        self.fullName = session.fullName
        self.expiresAt = session.expiresAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        userID = try container.decode(UUID.self, forKey: .userID)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        isEmailVerified = try container.decodeIfPresent(Bool.self, forKey: .isEmailVerified) ?? false
        fullName = try container.decodeIfPresent(String.self, forKey: .fullName)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    }

    var session: UserSession {
        UserSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userID: userID,
            email: email,
            isEmailVerified: isEmailVerified,
            fullName: fullName,
            expiresAt: expiresAt
        )
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
