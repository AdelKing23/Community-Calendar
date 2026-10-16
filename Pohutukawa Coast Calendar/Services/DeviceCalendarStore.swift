import Foundation
import Combine
import EventKit

@MainActor
final class DeviceCalendarStore: ObservableObject {
    enum AddResult: Equatable {
        case added
        case alreadyAdded
        case denied
        case unavailable
        case failed
    }

    enum RemoveResult: Equatable {
        case removed
        case notFound
        case denied
        case failed
    }

    @Published private(set) var lastResult: AddResult?
    @Published private(set) var calendarEventIDs: [String: String]

    private let eventStore = EKEventStore()
    private let defaults: UserDefaults
    private let savedEventKey = "community_calendar_device_calendar_event_ids"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.calendarEventIDs = defaults.dictionary(forKey: savedEventKey) as? [String: String] ?? [:]
    }

    func hasAddedCalendarEvent(for event: LocalEvent) -> Bool {
        calendarEventIDs[event.id.uuidString] != nil
    }

    func refreshCalendarState(for event: LocalEvent) async {
        guard let calendarEventID = savedCalendarEventID(for: event) else { return }

        guard hasReadableCalendarAccess() else { return }

        if eventStore.event(withIdentifier: calendarEventID) == nil {
            forgetCalendarEvent(for: event)
        }
    }

    func isCalendarAccessDenied() -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .denied, .restricted:
            return true
        default:
            return false
        }
    }

    func addToCalendar(_ event: LocalEvent, alarmLeadTime: EventReminderLeadTime? = nil) async -> AddResult {
        guard event.listingKind == .event, event.startDate > Date().addingTimeInterval(-60) else {
            lastResult = .unavailable
            return .unavailable
        }

        if let calendarEventID = savedCalendarEventID(for: event) {
            guard hasReadableCalendarAccess() else {
                lastResult = .alreadyAdded
                return .alreadyAdded
            }

            if eventStore.event(withIdentifier: calendarEventID) != nil {
                lastResult = .alreadyAdded
                return .alreadyAdded
            }

            forgetCalendarEvent(for: event)
        }

        let authorized = await requestCalendarWriteAccess()
        guard authorized else {
            lastResult = .denied
            return .denied
        }

        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            lastResult = .unavailable
            return .unavailable
        }

        let calendarEvent = EKEvent(eventStore: eventStore)
        calendarEvent.calendar = calendar
        calendarEvent.title = event.title
        calendarEvent.startDate = event.startDate
        calendarEvent.endDate = max(event.endDate, event.startDate.addingTimeInterval(60 * 60))
        calendarEvent.location = "\(event.venue), \(event.displayLocationName)"
        calendarEvent.notes = [
            event.shortDescription,
            event.priceLabel.isEmpty ? nil : "Cost: \(event.priceLabel)",
            event.contactEmail.map { "Contact: \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")

        if let alarmLeadTime {
            calendarEvent.addAlarm(EKAlarm(relativeOffset: -alarmLeadTime.seconds))
        }

        do {
            try eventStore.save(calendarEvent, span: .thisEvent)
            saveCalendarEventID(calendarEvent.eventIdentifier, for: event)
            lastResult = .added
            return .added
        } catch {
            lastResult = .failed
            return .failed
        }
    }

    func removeFromCalendar(_ event: LocalEvent) async -> RemoveResult {
        guard let calendarEventID = savedCalendarEventID(for: event) else {
            return .notFound
        }

        let authorized = await requestCalendarFullAccess()
        guard authorized else {
            return .denied
        }

        guard let calendarEvent = eventStore.event(withIdentifier: calendarEventID) else {
            forgetCalendarEvent(for: event)
            return .notFound
        }

        do {
            try eventStore.remove(calendarEvent, span: .thisEvent)
            forgetCalendarEvent(for: event)
            return .removed
        } catch {
            return .failed
        }
    }

    private func hasReadableCalendarAccess() -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            return true
        default:
            return false
        }
    }

    private func requestCalendarWriteAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .fullAccess, .authorized, .writeOnly:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            if #available(iOS 17.0, *) {
                do {
                    return try await eventStore.requestWriteOnlyAccessToEvents()
                } catch {
                    return false
                }
            } else {
                return await withCheckedContinuation { continuation in
                    eventStore.requestAccess(to: .event) { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
            }
        @unknown default:
            return false
        }
    }

    private func requestCalendarFullAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)

        switch status {
        case .fullAccess, .authorized:
            return true
        case .writeOnly:
            if #available(iOS 17.0, *) {
                do {
                    return try await eventStore.requestFullAccessToEvents()
                } catch {
                    return false
                }
            } else {
                return false
            }
        case .denied, .restricted:
            return false
        case .notDetermined:
            if #available(iOS 17.0, *) {
                do {
                    return try await eventStore.requestFullAccessToEvents()
                } catch {
                    return false
                }
            } else {
                return await withCheckedContinuation { continuation in
                    eventStore.requestAccess(to: .event) { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
            }
        @unknown default:
            return false
        }
    }

    private func savedCalendarEventID(for event: LocalEvent) -> String? {
        calendarEventIDs[event.id.uuidString]
    }

    private func saveCalendarEventID(_ calendarEventID: String, for event: LocalEvent) {
        calendarEventIDs[event.id.uuidString] = calendarEventID
        persist()
    }

    private func forgetCalendarEvent(for event: LocalEvent) {
        calendarEventIDs.removeValue(forKey: event.id.uuidString)
        persist()
    }

    private func persist() {
        defaults.set(calendarEventIDs, forKey: savedEventKey)
    }
}
