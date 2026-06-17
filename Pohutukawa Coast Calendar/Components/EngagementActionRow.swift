import SwiftUI

struct EngagementActionRow: View {
    let event: LocalEvent
    private let analyticsService: EventAnalyticsRecording = SupabaseEventService()

    @EnvironmentObject private var engagementStore: EventEngagementStore
    @EnvironmentObject private var reminderStore: EventReminderStore
    @EnvironmentObject private var userSessionStore: UserSessionStore

    var body: some View {
        HStack(spacing: 5) {
            EngagementButton(title: "Interested", icon: "star", isSelected: engagementStore.isInterested(event)) {
                engagementStore.toggleInterested(event)
                recordAnalytics("interested")
            }

            EngagementButton(title: "Going", icon: "checkmark.circle", isSelected: engagementStore.isGoing(event)) {
                toggleGoing()
            }

            EngagementButton(title: "Save", icon: "bookmark", isSelected: engagementStore.isSaved(event)) {
                engagementStore.toggleSaved(event)
                recordAnalytics("save")
            }

            ShareLink(item: shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(PCCTheme.ink.opacity(0.66))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 4)
                    .background(PCCTheme.cream.opacity(0.66), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    recordAnalytics("share")
                }
            )
        }
    }

    private func toggleGoing() {
        let isGoing = engagementStore.toggleGoing(event)
        reminderStore.syncReminder(for: event, isGoing: isGoing)
        recordAnalytics("going")
    }

    private func recordAnalytics(_ eventType: String) {
        Task {
            await userSessionStore.refreshIfNeeded()
            try? await analyticsService.recordEventAnalytics(
                eventID: event.id,
                eventType: eventType,
                source: "engagement_row",
                locationScopeID: nil,
                accessToken: userSessionStore.session?.accessToken
            )
        }
    }

    private var shareText: String {
        """
        \(event.title)
        \(event.dateText)
        \(event.timeText)
        \(event.venue), \(event.displayLocationName)

        Shared from Pohutukawa Coast Calendar.
        """
    }
}

struct EngagementButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: isSelected ? "\(icon).fill" : icon)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(isSelected ? PCCTheme.leafGreen : PCCTheme.ink.opacity(0.66))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 4)
                .background(
                    isSelected ? PCCTheme.leafGreen.opacity(0.12) : PCCTheme.cream.opacity(0.66),
                    in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}
