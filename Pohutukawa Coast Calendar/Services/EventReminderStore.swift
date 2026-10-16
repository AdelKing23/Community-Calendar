import Foundation
import Combine
import UserNotifications

final class CoastCalendarNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CoastCalendarNotificationDelegate()

    private override init() {
        super.init()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        NotificationCenter.default.post(
            name: .coastCalendarDidOpenRemoteNotification,
            object: nil,
            userInfo: [CoastCalendarRemoteNotificationUserInfo.payload: response.notification.request.content.userInfo]
        )
    }
}

enum EventReminderLeadTime: String, CaseIterable, Identifiable {
    case atStart
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case twoHours
    case oneDay
    case oneWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .atStart: return "At start time"
        case .fiveMinutes: return "5 minutes before"
        case .fifteenMinutes: return "15 minutes before"
        case .thirtyMinutes: return "30 minutes before"
        case .oneHour: return "1 hour before"
        case .twoHours: return "2 hours before"
        case .oneDay: return "1 day before"
        case .oneWeek: return "1 week before"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .atStart: return 0
        case .fiveMinutes: return 5 * 60
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .twoHours: return 2 * 60 * 60
        case .oneDay: return 24 * 60 * 60
        case .oneWeek: return 7 * 24 * 60 * 60
        }
    }
}

@MainActor
final class EventReminderStore: ObservableObject {
    enum ScheduleResult: Equatable {
        case scheduled(Date)
        case denied
        case unavailable
        case failed
    }

    @Published private(set) var reminderEventIDs: Set<UUID>
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var automaticGoingRemindersEnabled: Bool {
        didSet {
            defaults.set(automaticGoingRemindersEnabled, forKey: automaticGoingRemindersKey)
            if !automaticGoingRemindersEnabled {
                cancelAllReminders()
            }
        }
    }
    @Published var reminderLeadTime: EventReminderLeadTime {
        didSet {
            defaults.set(reminderLeadTime.rawValue, forKey: reminderLeadTimeKey)
        }
    }

    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter
    private let reminderKey = "community_calendar_event_reminders"
    private let automaticGoingRemindersKey = "community_calendar_automatic_going_reminders"
    private let reminderLeadTimeKey = "community_calendar_reminder_lead_time"
    private let eventReminderLeadTimesKey = "community_calendar_event_reminder_lead_times"

    init(
        defaults: UserDefaults = .standard,
        center: UNUserNotificationCenter = .current()
    ) {
        self.defaults = defaults
        self.center = center
        self.center.delegate = CoastCalendarNotificationDelegate.shared
        reminderEventIDs = Self.loadSet(forKey: reminderKey, defaults: defaults)
        automaticGoingRemindersEnabled = defaults.object(forKey: automaticGoingRemindersKey) as? Bool ?? true
        reminderLeadTime = EventReminderLeadTime(rawValue: defaults.string(forKey: reminderLeadTimeKey) ?? "") ?? .oneHour

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

    func leadTime(for event: LocalEvent) -> EventReminderLeadTime {
        let overrides = defaults.dictionary(forKey: eventReminderLeadTimesKey) as? [String: String] ?? [:]
        return EventReminderLeadTime(rawValue: overrides[event.id.uuidString] ?? "") ?? reminderLeadTime
    }

    func reminderTitle(for event: LocalEvent) -> String {
        hasReminder(for: event) ? leadTime(for: event).title : "Off"
    }

    func syncReminder(for event: LocalEvent, isGoing: Bool) {
        if isGoing, automaticGoingRemindersEnabled {
            Task { await scheduleReminder(for: event, leadTime: leadTime(for: event)) }
        } else {
            cancelReminder(for: event)
        }
    }

    @discardableResult
    func scheduleReminder(for event: LocalEvent, leadTime: EventReminderLeadTime? = nil) async -> ScheduleResult {
        guard event.startDate > Date().addingTimeInterval(60) else {
            cancelReminder(for: event)
            return .unavailable
        }

        let selectedLeadTime = leadTime ?? self.leadTime(for: event)
        setLeadTime(selectedLeadTime, for: event)

        let isAllowed = await requestAuthorizationIfNeeded()
        guard isAllowed else { return .denied }

        center.removePendingNotificationRequests(withIdentifiers: [notificationID(for: event.id)])

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = "Starts \(event.timeText) at \(event.venue), \(event.town.rawValue)."
        content.sound = .default
        content.userInfo = [
            "event_id": event.id.uuidString,
            "event_title": event.title
        ]

        let triggerDate = reminderDate(for: event, leadTime: selectedLeadTime)
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
            await refreshAuthorizationStatus()
            return .scheduled(triggerDate)
        } catch {
            reminderEventIDs.remove(event.id)
            persist()
            return .failed
        }
    }

    func cancelReminder(for event: LocalEvent) {
        center.removePendingNotificationRequests(withIdentifiers: [notificationID(for: event.id)])
        reminderEventIDs.remove(event.id)
        persist()
    }

    func cancelAllReminders() {
        let identifiers = reminderEventIDs.map { notificationID(for: $0) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        reminderEventIDs.removeAll()
        persist()
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    @discardableResult
    func requestNotificationAccess() async -> Bool {
        return await requestAuthorizationIfNeeded()
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

    private func setLeadTime(_ leadTime: EventReminderLeadTime, for event: LocalEvent) {
        var overrides = defaults.dictionary(forKey: eventReminderLeadTimesKey) as? [String: String] ?? [:]
        overrides[event.id.uuidString] = leadTime.rawValue
        defaults.set(overrides, forKey: eventReminderLeadTimesKey)
    }

    private func reminderDate(for event: LocalEvent, leadTime: EventReminderLeadTime) -> Date {
        let preferredDate = event.startDate.addingTimeInterval(-leadTime.seconds)
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
