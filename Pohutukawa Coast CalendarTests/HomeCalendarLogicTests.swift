import XCTest
@testable import Pohutukawa_Coast_Calendar

final class HomeCalendarLogicTests: XCTestCase {
    private let calendar = HomeCalendarLogic.calendar(timeZone: TimeZone(identifier: "Pacific/Auckland")!)

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func event(
        _ title: String,
        category: EventCategory,
        topics: [EventCategory] = [],
        start: Date,
        end: Date,
        createdAt: Date = .distantPast,
        promotionRank: Int = 0,
        isFeatured: Bool = false
    ) -> LocalEvent {
        var event = LocalEvent(
            title: title,
            category: category,
            town: .beachlands,
            venue: "Hall",
            startDate: start,
            endDate: end,
            priceLabel: "Free",
            isFree: true,
            audience: "Everyone",
            shortDescription: "",
            longDescription: "",
            contactPhone: nil,
            contactEmail: nil,
            isFeatured: isFeatured,
            isPaidPush: false,
            createdAt: createdAt,
            activePromotionRank: promotionRank
        )
        event.topics = topics
        return event
    }

    func testGridIsMondayFirst() {
        // 1 November 2026 is a Sunday, so it sits in the 7th column.
        let cells = HomeCalendarLogic.gridCells(forMonthStarting: date(2026, 11, 1, 0), calendar: calendar)
        XCTAssertEqual(cells.prefix(6).filter { $0 == nil }.count, 6)
        XCTAssertEqual(cells.compactMap { $0 }.count, 30)
        XCTAssertEqual(calendar.component(.day, from: cells[6]!), 1)
    }

    func testMonthStartsBeginWithCurrentMonth() {
        let months = HomeCalendarLogic.monthStarts(from: date(2026, 11, 14), count: 3, calendar: calendar)
        XCTAssertEqual(months.map { calendar.component(.month, from: $0) }, [11, 12, 1])
        XCTAssertEqual(calendar.component(.day, from: months[0]), 1)
    }

    func testSameTopicCollapsesToOneDotAndTopicsFallBackToCategory() {
        let monthStart = date(2026, 11, 1, 0)
        let events = (0..<5).map { index in
            event("Gig \(index)", category: .liveMusic, start: date(2026, 11, 20, 18 + index % 3), end: date(2026, 11, 20, 22))
        } + [
            event("Market", category: .community, topics: [.markets, .foodDrink], start: date(2026, 11, 20, 8), end: date(2026, 11, 20, 12))
        ]

        let grouped = HomeCalendarLogic.topicsByDay(events, monthStart: monthStart, calendar: calendar)
        XCTAssertEqual(grouped[calendar.startOfDay(for: date(2026, 11, 20))], [.liveMusic, .foodDrink, .markets])
    }

    func testMultiDayListingMarksEveryOverlappedDayInsideTheMonth() {
        let monthStart = date(2026, 11, 1, 0)
        let festival = event("Festival", category: .community, start: date(2026, 11, 28, 9), end: date(2026, 12, 2, 17))
        let grouped = HomeCalendarLogic.topicsByDay([festival], monthStart: monthStart, calendar: calendar)
        XCTAssertEqual(Set(grouped.keys.map { calendar.component(.day, from: $0) }), [28, 29, 30])

        let december = HomeCalendarLogic.topicsByDay([festival], monthStart: date(2026, 12, 1, 0), calendar: calendar)
        XCTAssertEqual(Set(december.keys.map { calendar.component(.day, from: $0) }), [1, 2])
    }

    func testOverlapExcludesListingEndingBeforeTheDay() {
        let earlier = event("Earlier", category: .sport, start: date(2026, 11, 19, 9), end: date(2026, 11, 19, 23, 59))
        XCTAssertFalse(HomeCalendarLogic.event(earlier, overlapsDay: date(2026, 11, 20), calendar: calendar))
        XCTAssertTrue(HomeCalendarLogic.event(earlier, overlapsDay: date(2026, 11, 19), calendar: calendar))
    }

    func testDayOrderingPutsHigherPlacementFirstThenFirstListed() {
        let day = date(2026, 11, 20)
        let freeEarly = event("Free early", category: .community, start: day, end: day, createdAt: date(2026, 11, 1))
        let freeLate = event("Free late", category: .community, start: day, end: day, createdAt: date(2026, 11, 5))
        let boosted = event("Boosted", category: .community, start: day, end: day, createdAt: date(2026, 11, 9), promotionRank: 1)
        let top = event("Top", category: .community, start: day, end: day, createdAt: date(2026, 11, 10), promotionRank: 2)
        let featured = event("Featured", category: .community, start: day, end: day, createdAt: date(2026, 11, 8), isFeatured: true)

        let ordered = HomeCalendarLogic.dayEvents([freeLate, featured, freeEarly, boosted, top], on: day, calendar: calendar)
        XCTAssertEqual(ordered.map(\.title), ["Top", "Boosted", "Featured", "Free early", "Free late"])
    }

    func testFinishedListingsAreHiddenLikeHome() {
        let now = date(2026, 11, 14, 12)
        let finished = event("Finished", category: .sport, start: date(2026, 11, 14, 8), end: date(2026, 11, 14, 9))
        let running = event("Running", category: .sport, start: date(2026, 11, 14, 8), end: date(2026, 11, 14, 15))
        XCTAssertFalse(HomeCalendarLogic.isShownOnHome(finished, now: now))
        XCTAssertTrue(HomeCalendarLogic.isShownOnHome(running, now: now))
    }

    func testPaletteHasTwelveDistinctColours() {
        let values = EventCategory.allCases.map(PCCTopicPalette.hex(for:))
        XCTAssertEqual(values.count, 12)
        XCTAssertEqual(Set(values).count, 12)
    }
}
