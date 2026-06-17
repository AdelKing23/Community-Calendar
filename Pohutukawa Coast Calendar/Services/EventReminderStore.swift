import Foundation
import Combine
import UserNotifications

@MainActor
final class EventReminderStore: ObservableObject {
    @Published private(set) var reminderEventIDs: Set<UUID>
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter
    private let reminderKey = "community_calendar_event_reminders"
    private let reminderLeadTime: TimeInterval = 60 * 60

    init(
        defaults: UserDefaults = .standard,
        center: UNUserNotificationCenter = .current()
    ) {
        self.defaults = defaults
        self.center = center
        reminderEventIDs = Self.loadSet(forKey: reminderKey, defaults: defaults)

        Task {
            await refreshAuthorizationStatus()
            await syncPendingReminderState()
        }
    }

    var activeReminderCount: Int {
        reminderEventIDs.count
    }

    func hasReminder(for event: LocalEvent) -> Bool {
        reminderEventIDs.contains(event.id)
    }

    func syncReminder(for event: LocalEvent, isGoing: Bool) {
        if isGoing {
            Task { await scheduleReminder(for: event) }
        } else {
            cancelReminder(for: event)
        }
    }

    func scheduleReminder(for event: LocalEvent) async {
        guard event.startDate > Date().addingTimeInterval(60) else {
            cancelReminder(for: event)
            return
        }

        let isAllowed = await requestAuthorizationIfNeeded()
        guard isAllowed else { return }

        center.removePendingNotificationRequests(withIdentifiers: [notificationID(for: event.id)])

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = "Starts \(event.timeText) at \(event.venue), \(event.town.rawValue)."
        content.sound = .default
        content.userInfo = [
            "event_id": event.id.uuidString,
            "event_title": event.title
        ]

        let triggerDate = reminderDate(for: event)
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: triggerDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationID(for: event.id),
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            reminderEventIDs.insert(event.id)
            persist()
        } catch {
            reminderEventIDs.remove(event.id)
            persist()
        }
    }

    func cancelReminder(for event: LocalEvent) {
        center.removePendingNotificationRequests(withIdentifiers: [notificationID(for: event.id)])
        reminderEventIDs.remove(event.id)
        persist()
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func syncPendingReminderState() async {
        let pending = await center.pendingNotificationRequests()
        let pendingEventIDs = Set(
            pending.compactMap { request -> UUID? in
                guard request.identifier.hasPrefix(Self.notificationPrefix) else { return nil }
                return UUID(uuidString: String(request.identifier.dropFirst(Self.notificationPrefix.count)))
            }
        )

        reminderEventIDs = reminderEventIDs.intersection(pendingEventIDs)
        persist()
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        await refreshAuthorizationStatus()

        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                await refreshAuthorizationStatus()
                return granted
            } catch {
                await refreshAuthorizationStatus()
                return false
            }
        @unknown default:
            return false
        }
    }

    private func reminderDate(for event: LocalEvent) -> Date {
        let preferredDate = event.startDate.addingTimeInterval(-reminderLeadTime)
        let minimumLeadDate = Date().addingTimeInterval(60)

        if preferredDate > minimumLeadDate {
            return preferredDate
        }

        return min(minimumLeadDate, event.startDate.addingTimeInterval(-30))
    }

    private func notificationID(for eventID: UUID) -> String {
        "\(Self.notificationPrefix)\(eventID.uuidString)"
    }

    private func persist() {
        defaults.set(reminderEventIDs.map(\.uuidString), forKey: reminderKey)
        objectWillChange.send()
    }

    private static let notificationPrefix = "community_calendar_event_reminder_"

    private static func loadSet(forKey key: String, defaults: UserDefaults) -> Set<UUID> {
        let values = defaults.stringArray(forKey: key) ?? []
        return Set(values.compactMap(UUID.init(uuidString:)))
    }
}
