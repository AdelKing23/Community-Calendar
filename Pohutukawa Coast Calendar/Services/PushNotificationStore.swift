import Combine
import Foundation
import UIKit
import UserNotifications

protocol PushNotificationRegistering {
    func upsertPushDeviceToken(_ registration: PushDeviceTokenRegistration, accessToken: String) async throws
    func deletePushDeviceToken(token: String, userID: UUID, accessToken: String) async throws
}

struct PushDeviceTokenRegistration: Encodable {
    let userID: UUID
    let token: String
    let platform: String
    let environment: String
    let bundleID: String
    let appVersion: String?
    let deviceName: String?
    let lastSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case token
        case platform
        case environment
        case bundleID = "bundle_id"
        case appVersion = "app_version"
        case deviceName = "device_name"
        case lastSeenAt = "last_seen_at"
    }
}

@MainActor
final class PushNotificationStore: ObservableObject {
    @Published private(set) var isRegisteredForPush = false
    @Published private(set) var lastMessage: String?

    private let service: PushNotificationRegistering
    private let notificationCenter: UNUserNotificationCenter
    private var activeSession: UserSession?
    private var activeContext = UserAccountContext(userID: nil, generation: 0)
    private var currentDeviceToken: String?
    private var observers: [NSObjectProtocol] = []

    init(
        service: PushNotificationRegistering? = nil,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.service = service ?? SupabaseEventService()
        self.notificationCenter = notificationCenter
        observeApplicationCallbacks()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func syncSignedInSession(_ session: UserSession?, context: UserAccountContext) async {
        activeSession = session
        activeContext = context

        guard session != nil else {
            isRegisteredForPush = false
            currentDeviceToken = nil
            return
        }

        let settings = await notificationCenter.notificationSettings()
        if [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    @discardableResult
    func prepareForMembershipDecisionNotifications(session: UserSession, context: UserAccountContext) async -> Bool {
        activeSession = session
        activeContext = context

        let settings = await notificationCenter.notificationSettings()
        guard activeContext == context,
              activeSession?.userID == context.userID else { return false }

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
            lastMessage = "Membership notifications are ready."
            return true
        case .notDetermined:
            do {
                let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
                guard activeContext == context,
                      activeSession?.userID == context.userID else { return false }
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                    lastMessage = "Membership notifications are ready."
                } else {
                    lastMessage = "Notifications are off. Check the app later for your membership decision."
                }
                return granted
            } catch {
                lastMessage = "Notifications could not be enabled. Check the app later for your membership decision."
                return false
            }
        case .denied:
            lastMessage = "Notifications are off. Check the app later for your membership decision."
            return false
        @unknown default:
            lastMessage = "Notification status is unknown. Check the app later for your membership decision."
            return false
        }
    }

    func removeCurrentTokenBeforeSignOut() async {
        guard let session = activeSession, let currentDeviceToken else { return }

        do {
            try await service.deletePushDeviceToken(
                token: currentDeviceToken,
                userID: session.userID,
                accessToken: session.accessToken
            )
        } catch {
            lastMessage = "Push token cleanup will retry after next sign in."
        }

        self.currentDeviceToken = nil
        isRegisteredForPush = false
    }

    private func observeApplicationCallbacks() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .coastCalendarDidRegisterRemoteNotifications,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let token = notification.userInfo?[CoastCalendarRemoteNotificationUserInfo.deviceToken] as? Data else {
                    return
                }
                Task { @MainActor [weak self] in
                    await self?.registerDeviceToken(token)
                }
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .coastCalendarDidFailToRegisterRemoteNotifications,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let errorMessage = (notification.userInfo?[CoastCalendarRemoteNotificationUserInfo.error] as? Error)?.localizedDescription
                    ?? "Could not register for push notifications."
                Task { @MainActor [weak self] in
                    self?.lastMessage = errorMessage
                    self?.isRegisteredForPush = false
                }
            }
        )
    }

    private func registerDeviceToken(_ tokenData: Data) async {
        guard let session = activeSession else { return }
        let requestContext = activeContext

        let token = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        currentDeviceToken = token

        do {
            try await service.upsertPushDeviceToken(
                PushDeviceTokenRegistration(
                    userID: session.userID,
                    token: token,
                    platform: "ios",
                    environment: Self.apnsEnvironment,
                    bundleID: Bundle.main.bundleIdentifier ?? "com.atlasdigital.Pohutukawa-Coast-Calendar",
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                    deviceName: UIDevice.current.model,
                    lastSeenAt: Date()
                ),
                accessToken: session.accessToken
            )
            guard activeContext == requestContext,
                  activeSession?.userID == requestContext.userID else { return }
            isRegisteredForPush = true
            lastMessage = "Push notifications are connected."
        } catch {
            guard activeContext == requestContext else { return }
            isRegisteredForPush = false
            lastMessage = "Push notifications could not be connected: \(error.pccUserFacingMessage)"
        }
    }

    private static var apnsEnvironment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }
}
