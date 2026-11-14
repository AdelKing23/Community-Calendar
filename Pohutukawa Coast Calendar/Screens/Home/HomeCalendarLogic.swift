import Foundation

enum HomeViewMode: String {
    case board
    case calendar

    static let storageKey = "communityCalendar.home.viewMode"
}

/// Pure date and grouping rules for the Home calendar. Mirrors web/app/HomeCalendar.tsx.
enum HomeCalendarLogic {
    /// Months shown when the calendar first opens, how many more load per scroll, and the cap.
    nonisolated static let initialMonthCount = 3
    nonisolated static let monthsPerLoad = 2
    nonisolated static let maximumMonthCount = 18
    /// Dots shown under a day before collapsing the rest into a "+".
    nonisolated static let maximumVisibleDots = 4

    /// Monday-first Gregorian calendar in the device time zone (Pacific/Auckland on NZ phones).
    nonisolated static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    nonisolated static func monthStart(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Starts of `count` consecutive months, beginning with the month containing `now`.
    nonisolated static func monthStarts(from now: Date, count: Int, calendar: Calendar) -> [Date] {
        let first = monthStart(for: now, calendar: calendar)
        return (0..<max(0, count)).compactMap { calendar.date(byAdding: .month, value: $0, to: first) }
    }

    /// Grid cells for a month card: leading `nil` padding so the 1st sits under its weekday (Monday first).
    nonisolated static func gridCells(forMonthStarting monthStart: Date, calendar: Calendar) -> [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        let weekday = calendar.component(.weekday, from: monthStart)
        let padding = (weekday - calendar.firstWeekday + 7) % 7
        let days: [Date?] = range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: monthStart)
        }
        return Array(repeating: nil, count: padding) + days
    }

    /// Same overlap rule as DateScope.today: start < endOfDay && end >= startOfDay.
    nonisolated static func event(_ event: LocalEvent, overlapsDay day: Date, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        return event.startDate < end && max(event.endDate, event.startDate) >= start
    }

    /// Topics used for dots: event_topics first, falling back to the listing's primary category.
    nonisolated static func topics(for event: LocalEvent) -> [EventCategory] {
        event.topics.isEmpty ? [event.category] : event.topics
    }

    /// One entry per day (start of day) holding the distinct topics present that day,
    /// in EventCategory order. Multi-day listings mark every day they overlap.
    nonisolated static func topicsByDay(
        _ events: [LocalEvent],
        monthStart: Date,
        calendar: Calendar
    ) -> [Date: [EventCategory]] {
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return [:] }
        var sets: [Date: Set<EventCategory>] = [:]

        for event in events {
            let eventEnd = max(event.endDate, event.startDate)
            guard event.startDate < monthEnd, eventEnd >= monthStart else { continue }
            var day = calendar.startOfDay(for: max(event.startDate, monthStart))
            let topics = Set(topics(for: event))
            while day < monthEnd, HomeCalendarLogic.event(event, overlapsDay: day, calendar: calendar) {
                sets[day, default: []].formUnion(topics)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }

        let order = EventCategory.allCases
        return sets.mapValues { set in order.filter(set.contains) }
    }

    /// Listings for one day, highest placement first; within a placement, the first listed comes first.
    nonisolated static func dayEvents(_ events: [LocalEvent], on day: Date, calendar: Calendar) -> [LocalEvent] {
        events
            .filter { HomeCalendarLogic.event($0, overlapsDay: day, calendar: calendar) }
            .sorted(by: dayOrdering)
    }

    /// Day ordering. Organisation subscription tier is not exposed on public listings, so the best
    /// available signal is the listing's paid placement (active_event_promotions placement_rank and
    /// is_paid_push via effectivePromotionRank), then Featured. Ties: earliest created first.
    nonisolated static func dayOrdering(_ lhs: LocalEvent, _ rhs: LocalEvent) -> Bool {
        if lhs.effectivePromotionRank != rhs.effectivePromotionRank {
            return lhs.effectivePromotionRank > rhs.effectivePromotionRank
        }

        if lhs.effectivePromotionRank >= ListingPromotionPlacement.priorityFirst.rawValue,
           lhs.activePromotionPaidAt != rhs.activePromotionPaidAt {
            return (lhs.activePromotionPaidAt ?? .distantFuture) < (rhs.activePromotionPaidAt ?? .distantFuture)
        }

        if lhs.isFeatured != rhs.isFeatured {
            return lhs.isFeatured && !rhs.isFeatured
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }

        return lhs.startDate < rhs.startDate
    }

    /// Home visibility rule shared with web: published listings that have not finished yet.
    nonisolated static func isShownOnHome(_ event: LocalEvent, now: Date) -> Bool {
        event.listingStatus == .published && max(event.endDate, event.startDate) >= now
    }
}
