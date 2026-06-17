import XCTest
@testable import Pohutukawa_Coast_Calendar

final class CoreLogicTests: XCTestCase {
    func testPollDetailsParsesReviewBlock() {
        let text = """
        Listing kind: Poll

        Tell us what the village should do next.

        [POLL]
        Question: Best day for a market?

        Options:
        1. Friday
        2. Saturday
        3. Sunday

        Custom answer: Allowed, max 250 characters
        [/POLL]
        """

        let details = PollDetails(reviewText: text)

        XCTAssertEqual(details?.question, "Best day for a market?")
        XCTAssertEqual(details?.options, ["Friday", "Saturday", "Sunday"])
        XCTAssertEqual(details?.allowsCustomAnswer, true)
    }

    func testPollReviewBlockIsStrippedFromPublicDescription() {
        let text = """
        Listing kind: Poll

        Tell us what the village should do next.

        [POLL]
        Question: Best day for a market?

        Options:
        1. Friday
        2. Saturday

        Custom answer: Not allowed
        [/POLL]
        """

        let stripped = PollDetails.strippedReviewBlock(from: text)

        XCTAssertEqual(stripped, "Tell us what the village should do next.")
        XCTAssertFalse(stripped.contains("[POLL]"))
        XCTAssertFalse(stripped.contains("Listing kind: Poll"))
    }

    func testPendingPollDraftRequiresQuestionAndTwoOptions() {
        var draft = PendingListingDraft()
        draft.listingKind = .poll
        draft.title = "Community feedback"
        draft.pollQuestion = "Which day works best?"
        draft.pollOptions = ["Friday", "Saturday", ""]

        XCTAssertTrue(draft.canSubmit)

        draft.pollOptions = ["Friday", "", ""]

        XCTAssertFalse(draft.canSubmit)
    }

    func testPendingPollDraftCapsOptionsAtTen() {
        var draft = PendingListingDraft()
        draft.listingKind = .poll
        draft.title = "Community feedback"
        draft.pollQuestion = "Pick one"
        draft.pollOptions = (1...12).map { "Option \($0)" }

        XCTAssertEqual(draft.pollDetails?.options.count, PollDetails.maxOptions)
        XCTAssertEqual(draft.pollDetails?.options.last, "Option 10")
    }

    func testListingTierPlacementRulesAreDistinct() {
        XCTAssertEqual(ListingTier.communityFree.promotionPlacement, .standard)
        XCTAssertEqual(ListingTier.commercialStandard.promotionPlacement, .standard)
        XCTAssertEqual(ListingTier.boost.promotionPlacement, .topTen)
        XCTAssertEqual(ListingTier.boostInsights.promotionPlacement, .priorityFirst)
    }

    func testDiscoveryOrderingPlacesBoostInsightsAboveStandardBoosts() {
        let standardBoost = event(
            title: "Standard boost",
            start: date(2026, 6, 18, 10),
            promotionRank: ListingPromotionPlacement.topTen.rawValue,
            paidAt: date(2026, 6, 17, 8)
        )
        let boostInsights = event(
            title: "Boost insights",
            start: date(2026, 6, 18, 12),
            promotionRank: ListingPromotionPlacement.priorityFirst.rawValue,
            paidAt: date(2026, 6, 17, 9)
        )

        let ordered = [standardBoost, boostInsights].sorted(by: EventFeedOrdering.discovery)

        XCTAssertEqual(ordered.map(\.title), ["Boost insights", "Standard boost"])
    }

    func testPriorityPromotionTieUsesEarliestPaidAt() {
        let firstPaid = event(
            title: "First paid",
            start: date(2026, 6, 18, 12),
            promotionRank: ListingPromotionPlacement.priorityFirst.rawValue,
            paidAt: date(2026, 6, 17, 8)
        )
        let secondPaid = event(
            title: "Second paid",
            start: date(2026, 6, 18, 10),
            promotionRank: ListingPromotionPlacement.priorityFirst.rawValue,
            paidAt: date(2026, 6, 17, 9)
        )

        let ordered = [secondPaid, firstPaid].sorted(by: EventFeedOrdering.discovery)

        XCTAssertEqual(ordered.map(\.title), ["First paid", "Second paid"])
    }

    func testPromotionWindowDoesNotRunUntilAFarFutureEvent() {
        let now = date(2026, 6, 17, 9)
        let eventStart = date(2027, 6, 17, 10)
        let eventEnd = date(2027, 6, 17, 12)
        let requestedEnd = date(2027, 6, 17, 12)

        let window = PromotionWindowPolicy.clampedWindow(
            tier: .boost,
            eventStart: eventStart,
            eventEnd: eventEnd,
            requestedStart: now,
            requestedEnd: requestedEnd,
            now: now
        )

        XCTAssertEqual(window?.start, now)
        XCTAssertEqual(window?.duration, ListingTier.boost.maximumPromotionDuration)
    }

    func testPromotionWindowStopsAtEventEnd() {
        let now = date(2026, 6, 17, 9)
        let eventStart = date(2026, 6, 18, 10)
        let eventEnd = date(2026, 6, 18, 12)

        let window = PromotionWindowPolicy.clampedWindow(
            tier: .boostInsights,
            eventStart: eventStart,
            eventEnd: eventEnd,
            requestedStart: now,
            requestedEnd: nil,
            now: now
        )

        XCTAssertEqual(window?.start, now)
        XCTAssertEqual(window?.end, eventEnd)
    }

    func testPromotionWindowRejectsEndedOrStandardListings() {
        let now = date(2026, 6, 17, 9)
        let eventStart = date(2026, 6, 16, 10)
        let eventEnd = date(2026, 6, 16, 12)

        XCTAssertNil(
            PromotionWindowPolicy.clampedWindow(
                tier: .commercialStandard,
                eventStart: date(2026, 6, 18, 10),
                eventEnd: date(2026, 6, 18, 12),
                requestedStart: now,
                requestedEnd: nil,
                now: now
            )
        )

        XCTAssertNil(
            PromotionWindowPolicy.clampedWindow(
                tier: .boost,
                eventStart: eventStart,
                eventEnd: eventEnd,
                requestedStart: now,
                requestedEnd: nil,
                now: now
            )
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }

    private func event(
        title: String,
        start: Date,
        promotionRank: Int = 0,
        paidAt: Date? = nil
    ) -> LocalEvent {
        LocalEvent(
            title: title,
            category: .community,
            town: .beachlands,
            venue: "Beachlands Hall",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            priceLabel: "Free",
            isFree: true,
            audience: "Everyone",
            shortDescription: "Community listing",
            longDescription: "Community listing",
            contactPhone: nil,
            contactEmail: nil,
            isFeatured: false,
            isPaidPush: false,
            createdAt: start,
            activePromotionRank: promotionRank,
            activePromotionPaidAt: paidAt
        )
    }
}
