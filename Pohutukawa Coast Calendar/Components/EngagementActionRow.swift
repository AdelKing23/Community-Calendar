import SwiftUI
import UIKit

struct EngagementActionRow: View {
    let event: LocalEvent
    private let analyticsService: EventAnalyticsRecording = SupabaseEventService()

    @EnvironmentObject private var engagementStore: EventEngagementStore
    @EnvironmentObject private var reminderStore: EventReminderStore
    @EnvironmentObject private var deviceCalendarStore: DeviceCalendarStore
    @EnvironmentObject private var userSessionStore: UserSessionStore
    @State private var showPlanSheet = false

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
                    .contentShape(RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxHeight: 44)
            .clipped()
            .contentShape(RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
            .simultaneousGesture(
                TapGesture().onEnded {
                    recordAnalytics("share")
                }
            )
        }
        .sheet(isPresented: $showPlanSheet) {
            EventPlanSheet(event: event)
                .environmentObject(reminderStore)
                .environmentObject(deviceCalendarStore)
        }
    }

    private func toggleGoing() {
        let isGoing = engagementStore.toggleGoing(event)
        reminderStore.syncReminder(for: event, isGoing: isGoing)
        recordAnalytics("going")
        if isGoing {
            showPlanSheet = true
        }
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

struct EventPlanSheet: View {
    let event: LocalEvent

    @EnvironmentObject private var reminderStore: EventReminderStore
    @EnvironmentObject private var deviceCalendarStore: DeviceCalendarStore
    @EnvironmentObject private var engagementStore: EventEngagementStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLeadTime: EventReminderLeadTime = .oneHour
    @State private var reminderMessage: String?
    @State private var reminderNeedsSettings = false
    @State private var isSettingReminder = false
    @State private var calendarMessage: String?
    @State private var isAddingToCalendar = false
    @State private var isRemovingFromCalendar = false
    @State private var calendarAccessNeedsSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                PCCScreenBackground()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("PLAN THIS", systemImage: "sparkles")
                                .font(.caption.weight(.black))
                                .tracking(1.2)
                                .foregroundStyle(PCCTheme.pohutukawaOrange)

                            Text(event.title)
                                .font(.system(size: 28, weight: .black, design: .serif))
                                .foregroundStyle(PCCTheme.ink)

                            Text("\(event.dateText) · \(event.timeText)\n\(event.venue), \(event.displayLocationName)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PCCTheme.ink.opacity(0.62))
                        }
                        .padding(18)
                        .planSheetCardStyle()

                        VStack(alignment: .leading, spacing: 12) {
                            Label("Reminder alarm", systemImage: reminderStore.hasReminder(for: event) ? "alarm.waves.left.and.right.fill" : "alarm")
                                .font(.headline.weight(.black))
                                .foregroundStyle(PCCTheme.ink)

                            Picker("Reminder time", selection: $selectedLeadTime) {
                                ForEach(EventReminderLeadTime.allCases) { leadTime in
                                    Text(leadTime.title).tag(leadTime)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 128)

                            if let reminderMessage {
                                Text(reminderMessage)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(reminderNeedsSettings ? PCCTheme.pohutukawaOrange : PCCTheme.leafGreen)
                            }

                            HStack(spacing: 10) {
                                Button {
                                    if reminderNeedsSettings {
                                        openAppSettings()
                                    } else {
                                        setReminder()
                                    }
                                } label: {
                                    Label(reminderButtonTitle, systemImage: reminderButtonIcon)
                                        .frame(maxWidth: .infinity)
                                }
                                .disabled(isSettingReminder)
                                .buttonStyle(PlanPrimaryButtonStyle())

                                Button {
                                    reminderStore.cancelReminder(for: event)
                                    reminderMessage = "Reminder removed."
                                    reminderNeedsSettings = false
                                } label: {
                                    Image(systemName: "bell.slash.fill")
                                        .frame(width: 44, height: 44)
                                }
                                .disabled(!reminderStore.hasReminder(for: event))
                                .buttonStyle(PlanSecondaryButtonStyle())
                            }
                        }
                        .padding(18)
                        .planSheetCardStyle()

                        VStack(alignment: .leading, spacing: 12) {
                            Label("Device calendar", systemImage: calendarIcon)
                                .font(.headline.weight(.black))
                                .foregroundStyle(PCCTheme.ink)

                            Text(calendarSummary)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(PCCTheme.ink.opacity(0.62))

                            if let calendarMessage {
                                Text(calendarMessage)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(PCCTheme.pohutukawaOrange)
                            }

                            HStack(spacing: 10) {
                                Button {
                                    if calendarAccessNeedsSettings {
                                        openAppSettings()
                                    } else {
                                        addToCalendar()
                                    }
                                } label: {
                                    Label(calendarButtonTitle, systemImage: calendarButtonIcon)
                                        .frame(maxWidth: .infinity)
                                }
                                .disabled(isAddingToCalendar || isRemovingFromCalendar)
                                .buttonStyle(PlanPrimaryButtonStyle())

                                Button {
                                    removeFromCalendar()
                                } label: {
                                    Image(systemName: "calendar.badge.minus")
                                        .frame(width: 44, height: 44)
                                }
                                .disabled(isAddingToCalendar || isRemovingFromCalendar || !deviceCalendarStore.hasAddedCalendarEvent(for: event))
                                .buttonStyle(PlanSecondaryButtonStyle())
                            }
                        }
                        .padding(18)
                        .planSheetCardStyle()

                        Button {
                            reminderStore.cancelReminder(for: event)
                            if deviceCalendarStore.hasAddedCalendarEvent(for: event) {
                                removeFromCalendar()
                            }
                            _ = engagementStore.toggleGoing(event)
                            dismiss()
                        } label: {
                            Text("Not going")
                                .font(.headline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .foregroundStyle(PCCTheme.pohutukawaRed)
                                .background(PCCTheme.cream.opacity(0.92), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, PCCKeyboardSpacing.standardTopPadding)
                    .padding(.bottom, PCCKeyboardSpacing.standardBottomPadding)
                }
            }
            .navigationTitle("Going")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PCCTheme.leafGreen)
                }
            }
            .task(id: event.id) {
                selectedLeadTime = reminderStore.leadTime(for: event)
                calendarAccessNeedsSettings = deviceCalendarStore.isCalendarAccessDenied()
                reminderNeedsSettings = reminderStore.authorizationStatus == .denied
                await deviceCalendarStore.refreshCalendarState(for: event)
                if reminderStore.hasReminder(for: event) {
                    reminderMessage = "Reminder set for \(selectedLeadTime.title.lowercased())."
                }
            }
        }
    }

    private var reminderButtonTitle: String {
        if isSettingReminder {
            return "Setting"
        }

        return reminderNeedsSettings ? "Open iPhone Settings" : "Set reminder"
    }

    private var reminderButtonIcon: String {
        reminderNeedsSettings ? "gearshape.fill" : "bell.badge.fill"
    }

    private var calendarIcon: String {
        if deviceCalendarStore.hasAddedCalendarEvent(for: event) {
            return "calendar.badge.checkmark"
        }

        return calendarAccessNeedsSettings ? "gear.badge.questionmark" : "calendar.badge.plus"
    }

    private var calendarSummary: String {
        if deviceCalendarStore.hasAddedCalendarEvent(for: event) {
            return "Already added on this device."
        }

        if calendarAccessNeedsSettings {
            return "Calendar access is off for Coast Calendar. Open iPhone Settings, allow Calendar access, then come back and add it."
        }

        return "Add this listing to your iPhone Calendar with a \(selectedLeadTime.title.lowercased()) alert."
    }

    private var calendarButtonTitle: String {
        if isAddingToCalendar {
            return "Adding"
        }

        return calendarAccessNeedsSettings ? "Open iPhone Settings" : "Add to Calendar"
    }

    private var calendarButtonIcon: String {
        calendarAccessNeedsSettings ? "gearshape.fill" : "calendar.badge.plus"
    }

    private func addToCalendar() {
        guard !isAddingToCalendar else { return }
        isAddingToCalendar = true
        calendarMessage = nil

        Task {
            defer { isAddingToCalendar = false }
            let result = await deviceCalendarStore.addToCalendar(event, alarmLeadTime: selectedLeadTime)

            switch result {
            case .added:
                calendarMessage = "Added to your device calendar with a \(selectedLeadTime.title.lowercased()) alert."
            case .alreadyAdded:
                calendarMessage = "Already on your device calendar."
            case .denied:
                calendarAccessNeedsSettings = true
                calendarMessage = "Calendar access is off."
            case .unavailable:
                calendarMessage = "This listing cannot be added to Calendar yet."
            case .failed:
                calendarMessage = "Could not add this event. Please try again."
            }
        }
    }

    private func removeFromCalendar() {
        guard !isRemovingFromCalendar else { return }
        isRemovingFromCalendar = true
        calendarMessage = nil

        Task {
            defer { isRemovingFromCalendar = false }
            let result = await deviceCalendarStore.removeFromCalendar(event)

            switch result {
            case .removed:
                calendarMessage = "Removed from your device calendar."
            case .notFound:
                calendarMessage = "That calendar entry was already gone."
            case .denied:
                calendarAccessNeedsSettings = true
                calendarMessage = "Calendar access is off."
            case .failed:
                calendarMessage = "Could not remove this event. Please try again."
            }
        }
    }

    private func setReminder() {
        guard !isSettingReminder else { return }
        isSettingReminder = true
        reminderMessage = nil
        reminderNeedsSettings = false

        Task {
            defer { isSettingReminder = false }
            let result = await reminderStore.scheduleReminder(for: event, leadTime: selectedLeadTime)

            switch result {
            case .scheduled:
                reminderMessage = "Reminder set for \(selectedLeadTime.title.lowercased())."
            case .denied:
                reminderNeedsSettings = true
                reminderMessage = "Notifications are off. Open iPhone Settings to allow reminder alerts."
            case .unavailable:
                reminderMessage = "This event is too close or has already passed."
            case .failed:
                reminderMessage = "Could not set that reminder. Please try again."
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct PlanPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.black))
            .foregroundStyle(.white)
            .padding(.vertical, 13)
            .padding(.horizontal, 14)
            .background(PCCTheme.leafGreen.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

struct PlanSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.black))
            .foregroundStyle(PCCTheme.ink.opacity(configuration.isPressed ? 0.42 : 0.62))
            .background(PCCTheme.cream.opacity(0.72), in: RoundedRectangle(cornerRadius: PCCTheme.smallRadius, style: .continuous))
    }
}

private extension View {
    func planSheetCardStyle() -> some View {
        background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: PCCTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PCCTheme.cardRadius, style: .continuous)
                    .stroke(.white.opacity(0.92), lineWidth: 1)
            )
            .shadow(color: PCCTheme.deepGreen.opacity(0.10), radius: 18, x: 0, y: 10)
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
