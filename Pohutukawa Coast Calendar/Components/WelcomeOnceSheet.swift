import SwiftUI

/// t221: per-account welcome, shown once on first entry and dismissible.
/// Signed in: the server row in public.user_welcome_dismissals is the source of truth (once per account, all devices).
/// Signed out: a local flag on this device. Same copy as the web app (WELCOME_COPY in CommunityCalendarApp.tsx).
enum WelcomeCopy {
    static let version = 1
    static let title = "Welcome to Coast Calendar"
    static let body = "Kia ora, and welcome. Coast Calendar is where locals share what’s on nearby: events, polls and notices from community groups and local organisations."
    static let tips = [
        "Browse Home, or switch to the calendar view to see what’s on each day.",
        "Choose your area to see what’s close to you.",
        "Save listings to My Calendar so you don’t miss them.",
        "Organisations can create an account and apply in Settings to start listing.",
        "Questions or feedback? Send us a Support message any time."
    ]
    static let signOff = "Ngā mihi nui."
    static let button = "Get started"
}

/// t224: when to show the welcome. Signed in: the server row decides, but a server error shows it
/// (fail open) unless this device already recorded this account's dismissal. Signed out: the device flag.
enum WelcomeGate {
    enum ServerCheck: Equatable { case dismissed, notDismissed, failed }

    static func shouldShow(signedIn: Bool, server: ServerCheck, dismissedOnThisDevice: Bool, signedOutDismissed: Bool) -> Bool {
        guard signedIn else { return !signedOutDismissed }
        switch server {
        case .dismissed: return false
        case .notDismissed, .failed: return !dismissedOnThisDevice
        }
    }

    /// Account IDs (lowercased) that dismissed the welcome on this device, stored comma-separated.
    static func accounts(from raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map { String($0) }.filter { !$0.isEmpty })
    }

    static func adding(_ userID: UUID, to raw: String) -> String {
        var ids = accounts(from: raw)
        ids.insert(userID.uuidString.lowercased())
        return ids.sorted().joined(separator: ",")
    }
}

enum WelcomeDismissalService {
    private static let resource = "user_welcome_dismissals"

    /// true = this account already dismissed the current welcome; false = show it; throws on network/server errors.
    static func hasDismissed(session: UserSession) async throws -> Bool {
        guard let base = SupabaseConfiguration.restURL,
              var components = URLComponents(url: base.appendingPathComponent(resource), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "select", value: "welcome_version"),
            URLQueryItem(name: "user_id", value: "eq.\(session.userID.uuidString.lowercased())"),
            URLQueryItem(name: "welcome_version", value: "eq.\(WelcomeCopy.version)")
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(for: request(url: url, session: session))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let rows = (try? JSONSerialization.jsonObject(with: data)) as? [Any] ?? []
        return !rows.isEmpty
    }

    static func recordDismissed(session: UserSession) async throws {
        guard let url = SupabaseConfiguration.restURL?.appendingPathComponent(resource) else { throw URLError(.badURL) }
        var request = request(url: url, session: session)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=ignore-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "user_id": session.userID.uuidString.lowercased(),
            "welcome_version": WelcomeCopy.version
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private static func request(url: URL, session: UserSession) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(SupabaseConfiguration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }
}

struct WelcomeOnceSheet: View {
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(WelcomeCopy.body)
                        .font(.body)
                        .foregroundStyle(PCCTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(WelcomeCopy.tips, id: \.self) { tip in
                            Label(tip, systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(PCCTheme.ink.opacity(0.82))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text(WelcomeCopy.signOff)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PCCTheme.ink)
                    Button(action: dismiss) {
                        Text(WelcomeCopy.button)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PCCTheme.pohutukawaRed)
                    .accessibilityIdentifier("welcome.getStarted")
                }
                .padding(20)
            }
            .navigationTitle(WelcomeCopy.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
