import XCTest
@testable import Pohutukawa_Coast_Calendar

/// t222: editing an all-day listing keeps it all-day, and NZ day helpers.
final class ListingEditAllDayTests: XCTestCase {
    private var nz: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        return calendar
    }

    private func listing(start: Date, end: Date, allDay: Bool) -> LocalEvent {
        LocalEvent(
            title: "Market", category: EventCategory.allCases.first!, town: .beachlands, venue: "Hall",
            startDate: start, endDate: end, priceLabel: "Free", isFree: true, audience: "Everyone",
            shortDescription: "Stalls", longDescription: "Stalls", contactPhone: nil, contactEmail: nil,
            isFeatured: false, isPaidPush: false, isAllDay: allDay
        )
    }

    func testAllDayEditKeepsAllDayAndNZBounds() {
        let start = nz.date(from: DateComponents(year: 2026, month: 11, day: 20))!
        let end = start.addingTimeInterval(86_399)
        let draft = ListingEditDraft(event: listing(start: start, end: end, allDay: true))
        XCTAssertFalse(draft.hasTime)
        XCTAssertEqual(draft.startDate, start)
        XCTAssertEqual(draft.endDate, end)
        XCTAssertEqual(draft.proposedChanges["is_all_day"], .bool(true))
    }

    func testAllDayEditGivenATimeGetsTwoHours() {
        let start = nz.date(from: DateComponents(year: 2026, month: 11, day: 20))!
        var draft = ListingEditDraft(event: listing(start: start, end: start.addingTimeInterval(86_399), allDay: true))
        draft.hasTime = true
        XCTAssertEqual(draft.endDate.timeIntervalSince(draft.startDate), 2 * 60 * 60)
        XCTAssertEqual(draft.proposedChanges["is_all_day"], .bool(false))
    }

    func testTimedEditStaysTimed() {
        let start = nz.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9))!
        let draft = ListingEditDraft(event: listing(start: start, end: start.addingTimeInterval(3 * 3600), allDay: false))
        XCTAssertTrue(draft.hasTime)
        XCTAssertEqual(draft.endDate.timeIntervalSince(draft.startDate), 3 * 3600)
        XCTAssertEqual(draft.proposedChanges["is_all_day"], .bool(false))
    }

    func testNZDayLocalDateMatchesNZCalendarDay() {
        let nzMidnight = nz.date(from: DateComponents(year: 2026, month: 9, day: 27))!
        let local = NZDay.localDate(for: nzMidnight)
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: local)
        XCTAssertEqual([parts.year, parts.month, parts.day], [2026, 9, 27])
    }
}
