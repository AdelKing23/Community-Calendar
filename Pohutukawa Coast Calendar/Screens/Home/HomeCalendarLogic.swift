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

    /// Listings for one day in Home calendar order (see `dayOrdering`).
    /// `planRanks` is the organisation subscription tier per listing when it becomes publicly readable;
    /// it is empty today, so paid placement is used as the tier proxy.
    nonisolated static func dayEvents(
        _ events: [LocalEvent],
        on day: Date,
        calendar: Calendar,
        planRanks: [UUID: Int] = [:]
    ) -> [LocalEvent] {
        events
            .filter { HomeCalendarLogic.event($0, overlapsDay: day, calendar: calendar) }
            .sorted { dayOrdering($0, $1, planRanks: planRanks) }
    }

    /// Boosted = any paid placement (Top Boost or Boosted via active_event_promotions, or is_paid_push).
    nonisolated static func isBoosted(_ event: LocalEvent) -> Bool {
        event.effectivePromotionRank > 0
    }

    /// Tier used to rank boosted listings. Real plan rank (placement_rank of the organisation's active
    /// subscription) wins when known; until it is public, Top Boost (2) above Boosted (1) is the proxy.
    nonisolated static func tierRank(_ event: LocalEvent, planRanks: [UUID: Int]) -> Int {
        planRanks[event.id] ?? event.effectivePromotionRank
    }

    /// Day ordering agreed with Isaac:
    /// 1. Boosted listings always above non-boosted, whatever the tier.
    /// 2. Among boosted, higher tier first.
    /// 3. Same tier (boosted or not): first listed (earliest created) first.
    /// Featured is not used: in source it is an editorial flag, not a paid placement.
    nonisolated static func dayOrdering(_ lhs: LocalEvent, _ rhs: LocalEvent, planRanks: [UUID: Int] = [:]) -> Bool {
        let lhsBoosted = isBoosted(lhs)
        let rhsBoosted = isBoosted(rhs)
        if lhsBoosted != rhsBoosted {
            return lhsBoosted
        }

        if lhsBoosted {
            let lhsTier = tierRank(lhs, planRanks: planRanks)
            let rhsTier = tierRank(rhs, planRanks: planRanks)
            if lhsTier != rhsTier {
                return lhsTier > rhsTier
            }
        }

        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }

        return lhs.startDate < rhs.startDate
    }

    /// Home visibility rule shared with web: a published listing shows until its end, then stays
    /// (marked Finished) until midnight at the end of its end date, then drops off. No cap on future listings.
    nonisolated static func isShownOnHome(_ event: LocalEvent, now: Date, calendar: Calendar) -> Bool {
        guard event.listingStatus == .published else { return false }
        let end = max(event.endDate, event.startDate)
        guard let archiveAt = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) else {
            return end >= now
        }
        return now < archiveAt
    }

    /// True once the listing has ended but is still shown until midnight.
    nonisolated static func isFinished(_ event: LocalEvent, now: Date) -> Bool {
        max(event.endDate, event.startDate) < now
    }
}
