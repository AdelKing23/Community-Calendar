import Foundation
import Combine

@MainActor
final class EventEngagementStore: ObservableObject {
    @Published private(set) var interestedEventIDs: Set<UUID>
    @Published private(set) var goingEventIDs: Set<UUID>
    @Published private(set) var savedEventIDs: Set<UUID>

    private let interestedKey = "community_calendar_interested_events"
    private let goingKey = "community_calendar_going_events"
    private let savedKey = "community_calendar_saved_events"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        interestedEventIDs = Self.loadSet(forKey: interestedKey, defaults: defaults)
        goingEventIDs = Self.loadSet(forKey: goingKey, defaults: defaults)
        savedEventIDs = Self.loadSet(forKey: savedKey, defaults: defaults)
    }

    private let defaults: UserDefaults

    func isInterested(_ event: LocalEvent) -> Bool {
        interestedEventIDs.contains(event.id)
    }

    func isGoing(_ event: LocalEvent) -> Bool {
        goingEventIDs.contains(event.id)
    }

    func isSaved(_ event: LocalEvent) -> Bool {
        savedEventIDs.contains(event.id)
    }

    func toggleInterested(_ event: LocalEvent) {
        toggle(event.id, in: &interestedEventIDs, key: interestedKey)
    }

    func toggleGoing(_ event: LocalEvent) {
        toggle(event.id, in: &goingEventIDs, key: goingKey)
    }

    func toggleSaved(_ event: LocalEvent) {
        toggle(event.id, in: &savedEventIDs, key: savedKey)
    }

    func engagementKind(for event: LocalEvent) -> [SavedEventKind] {
        var kinds: [SavedEventKind] = []
        if isSaved(event) { kinds.append(.saved) }
        if isInterested(event) { kinds.append(.interested) }
        if isGoing(event) { kinds.append(.going) }
        return kinds
    }

    private func toggle(_ id: UUID, in set: inout Set<UUID>, key: String) {
        if set.contains(id) {
            set.remove(id)
        } else {
            set.insert(id)
        }

        defaults.set(set.map(\.uuidString), forKey: key)
        objectWillChange.send()
    }

    private static func loadSet(forKey key: String, defaults: UserDefaults) -> Set<UUID> {
        let values = defaults.stringArray(forKey: key) ?? []
        return Set(values.compactMap(UUID.init(uuidString:)))
    }
}

enum SavedEventKind: String, Identifiable, Hashable {
    case saved = "Saved"
    case interested = "Interested"
    case going = "Going"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .saved: return "bookmark.fill"
        case .interested: return "star.fill"
        case .going: return "checkmark.circle.fill"
        }
    }
}
