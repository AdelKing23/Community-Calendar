import Combine
import SwiftUI

protocol HomeCalendarEventFetching {
    func fetchHomeCalendarEventIDs(locationScopeID: String) async throws -> [UUID]
    func fetchHomeCalendarEvents(eventIDs: [UUID]?, from rangeStart: Date, to rangeEnd: Date) async throws -> [LocalEvent]
}

extension SupabaseEventService: HomeCalendarEventFetching {}

/// Loads Home calendar months on demand with the same location scope as the Home board.
@MainActor
final class HomeCalendarStore: ObservableObject {
    @Published private(set) var monthStarts: [Date] = []
    @Published private(set) var eventsByMonth: [Date: [LocalEvent]] = [:]
    @Published private(set) var loadingMonths: Set<Date> = []
    @Published private(set) var failedMonths: Set<Date> = []

    let calendar = HomeCalendarLogic.calendar()
    private let service: HomeCalendarEventFetching
    private var scopeID: String?
    private var scopedEventIDs: [UUID]?
    private var usesLocalScopeFilter = false
    /// Organisation plan rank per listing. Empty until plan rank is publicly readable
    /// (see CoastCalendar-backups/proposed-plan-rank-on-public-events.sql).
    private var planRanks: [UUID: Int] = [:]

    init(service: HomeCalendarEventFetching? = nil) {
        self.service = service ?? SupabaseEventService()
    }

    var canLoadMore: Bool {
        monthStarts.count < HomeCalendarLogic.maximumMonthCount
    }

    func prepare(scope: LocationScope, now: Date = Date()) async {
        let currentMonth = HomeCalendarLogic.monthStart(for: now, calendar: calendar)
        if scopeID != scope.id || monthStarts.first != currentMonth {
            scopeID = scope.id
            eventsByMonth = [:]
            failedMonths = []
            monthStarts = HomeCalendarLogic.monthStarts(from: now, count: HomeCalendarLogic.initialMonthCount, calendar: calendar)
            await resolveScope(scope)
        }
        await loadMissingMonths(scope: scope, now: now)
    }

    func reload(scope: LocationScope) async {
        scopeID = nil
        await prepare(scope: scope)
    }

    func loadMore(scope: LocationScope) async {
        guard canLoadMore, let last = monthStarts.last else { return }
        let extra = (1...HomeCalendarLogic.monthsPerLoad).compactMap { calendar.date(byAdding: .month, value: $0, to: last) }
        monthStarts += extra.prefix(HomeCalendarLogic.maximumMonthCount - monthStarts.count)
        await loadMissingMonths(scope: scope, now: Date())
    }

    func retry(month: Date, scope: LocationScope) async {
        failedMonths.remove(month)
        await load(month: month, scope: scope, now: Date())
    }

    func topicsByDay(forMonth monthStart: Date) -> [Date: [EventCategory]] {
        HomeCalendarLogic.topicsByDay(eventsByMonth[monthStart] ?? [], monthStart: monthStart, calendar: calendar)
    }

    func events(on day: Date) -> [LocalEvent] {
        let month = HomeCalendarLogic.monthStart(for: day, calendar: calendar)
        return HomeCalendarLogic.dayEvents(eventsByMonth[month] ?? [], on: day, calendar: calendar, planRanks: planRanks)
    }

    private func resolveScope(_ scope: LocationScope) async {
        do {
            scopedEventIDs = try await service.fetchHomeCalendarEventIDs(locationScopeID: scope.id)
            usesLocalScopeFilter = false
        } catch {
            // Same fallback as the Home board: unscoped listings filtered on device.
            print("[HomeCalendar] scoped IDs failed scope=\(scope.id) error=\(error)")
            scopedEventIDs = nil
            usesLocalScopeFilter = true
        }
    }

    private func loadMissingMonths(scope: LocationScope, now: Date) async {
        for month in monthStarts where eventsByMonth[month] == nil && !loadingMonths.contains(month) && !failedMonths.contains(month) {
            await load(month: month, scope: scope, now: now)
        }
    }

    private func load(month: Date, scope: LocationScope, now: Date) async {
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: month) else { return }
        let requestedScope = scope.id
        loadingMonths.insert(month)
        defer { loadingMonths.remove(month) }

        do {
            // Start of today, so listings that ended earlier today still load (shown as Finished until midnight).
            let rangeStart = max(month, calendar.startOfDay(for: now))
            let events = try await service.fetchHomeCalendarEvents(eventIDs: scopedEventIDs, from: rangeStart, to: nextMonth)
            guard scopeID == requestedScope else { return }
            eventsByMonth[month] = events.filter { event in
                HomeCalendarLogic.isShownOnHome(event, now: now, calendar: calendar)
                    && (!usesLocalScopeFilter || scope.matches(event))
            }
        } catch {
            guard scopeID == requestedScope else { return }
            print("[HomeCalendar] month load failed month=\(month) error=\(error)")
            failedMonths.insert(month)
        }
    }
}

struct HomeViewModeToggle: View {
    @Binding var mode: HomeViewMode

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                mode = mode == .board ? .calendar : .board
            }
        } label: {
            Image(systemName: mode == .board ? "calendar" : "rectangle.stack")
                .font(.headline.weight(.black))
                .foregroundStyle(PCCTheme.leafGreen)
                .frame(width: 40, height: 40)
                .background(PCCTheme.leafGreen.opacity(0.10), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode == .board ? "Show calendar" : "Show board")
    }
}

struct HomeCalendarLegend: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(EventCategory.allCases) { category in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(PCCTopicPalette.color(for: category))
                            .frame(width: 8, height: 8)
                        Text(category.shortLabel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(PCCTheme.text)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.86), in: Capsule())
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dot colours show listing topics")
    }
}

struct HomeCalendarMonthCard: View {
    let monthStart: Date
    let topicsByDay: [Date: [EventCategory]]
    let calendar: Calendar
    let isLoading: Bool
    let didFail: Bool
    let onRetry: () -> Void
    let onSelectDay: (Date) -> Void

    private let weekdayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        let today = calendar.startOfDay(for: Date())
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(monthStart.formatted(.dateTime.month(.wide).year()))
                    .font(.headline.weight(.black))
                    .foregroundStyle(PCCTheme.ink)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(PCCTheme.pohutukawaOrange)
                } else if didFail {
                    Button("Try again", action: onRetry)
                        .font(.caption.weight(.black))
                        .foregroundStyle(PCCTheme.pohutukawaOrange)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(PCCTheme.text)
                        .accessibilityHidden(true)
                }

                ForEach(Array(HomeCalendarLogic.gridCells(forMonthStarting: monthStart, calendar: calendar).enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day, today: today)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        .padding(16)
        .pccCardStyle()
    }

    private func dayCell(_ day: Date, today: Date) -> some View {
        let start = calendar.startOfDay(for: day)
        let isPast = start < today
        let isToday = start == today
        let topics = topicsByDay[start] ?? []
        let visible = Array(topics.prefix(HomeCalendarLogic.maximumVisibleDots))
        let overflow = topics.count - visible.count

        return Button {
            onSelectDay(start)
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.subheadline.weight(isToday ? .black : .bold))
                    .foregroundStyle(isToday ? Color.white : PCCTheme.ink)
                    .frame(width: 30, height: 30)
                    .background(isToday ? PCCTheme.pohutukawaOrange : Color.clear, in: Circle())

                HStack(spacing: 2) {
                    ForEach(visible) { topic in
                        Circle()
                            .fill(PCCTopicPalette.color(for: topic))
                            .frame(width: 6, height: 6)
                    }
                    if overflow > 0 {
                        Text("+")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(PCCTheme.text)
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .opacity(isPast ? 0.32 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isPast)
        .accessibilityLabel(accessibilityText(day: day, topics: topics, isToday: isToday))
    }

    private func accessibilityText(day: Date, topics: [EventCategory], isToday: Bool) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let prefix = isToday ? "Today, \(date)" : date
        guard !topics.isEmpty else { return "\(prefix), nothing listed" }
        return "\(prefix), \(topics.map(\.shortLabel).joined(separator: ", "))"
    }
}

struct HomeCalendarDayScreen: View {
    let day: Date
    let areaName: String
    @ObservedObject var store: HomeCalendarStore
    @State private var openedEventID: UUID?

    private var events: [LocalEvent] {
        store.events(on: day)
    }

    var body: some View {
        ZStack {
            PCCScreenBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.title2.weight(.black))
                            .foregroundStyle(PCCTheme.ink)
                        Text(events.isEmpty ? "Around \(areaName)" : "\(events.count) \(events.count == 1 ? "listing" : "listings") around \(areaName)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PCCTheme.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .pccCardStyle()

                    if events.isEmpty {
                        FeedMessageCard(
                            icon: "calendar.badge.plus",
                            title: "Nothing listed for this day yet",
                            message: "This date is free around \(areaName). If your organisation has something on, list it so locals can find it.",
                            retry: nil
                        )
                    } else {
                        let now = Date()
                        ForEach(events) { event in
                            if HomeCalendarLogic.isFinished(event, now: now) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label("Finished", systemImage: "checkmark.circle")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(PCCTheme.text)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.white.opacity(0.86), in: Capsule())
                                        .accessibilityLabel("Finished listing")
                                    HomeBoardCard(event: event, onOpen: { openedEventID = event.id })
                                        .saturation(0.2)
                                        .opacity(0.6)
                                }
                            } else {
                                HomeBoardCard(event: event, onOpen: { openedEventID = event.id })
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
        }
        .navigationTitle(day.formatted(.dateTime.day().month(.abbreviated)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .navigationDestination(isPresented: Binding(
            get: { openedEventID != nil },
            set: { if !$0 { openedEventID = nil } }
        )) {
            if let event = events.first(where: { $0.id == openedEventID }) {
                EventDetailScreen(event: event)
            }
        }
    }
}
