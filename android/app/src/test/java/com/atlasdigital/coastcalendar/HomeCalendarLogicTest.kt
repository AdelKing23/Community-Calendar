package com.atlasdigital.coastcalendar

import com.atlasdigital.coastcalendar.data.model.CoastTown
import com.atlasdigital.coastcalendar.data.model.EventCategory
import com.atlasdigital.coastcalendar.data.model.ListingKind
import com.atlasdigital.coastcalendar.data.model.ListingStatus
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.feature.home.HomeCalendarLogic
import com.atlasdigital.coastcalendar.feature.home.HomeViewMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId

class HomeCalendarLogicTest {
    private val nz = ZoneId.of("Pacific/Auckland")

    private fun ev(id: String, start: String, end: String, cat: EventCategory = EventCategory.Markets, topics: List<EventCategory> = emptyList(),
                   created: String = "2026-11-01T00:00:00Z", paid: Boolean = false, status: ListingStatus = ListingStatus.Published) = LocalEvent(
        id = id, title = id, category = cat, topics = topics, town = CoastTown.Beachlands, locationDisplayName = null, venue = "",
        start = Instant.parse(start), end = Instant.parse(end), priceLabel = "Free", isFree = true, shortDescription = "", longDescription = "",
        businessProfileId = null, organisationName = null, contactName = null, isFeatured = false, isPaidPush = paid, status = status,
        kind = ListingKind.Event, pollDetails = null, isAllDay = false, createdAt = Instant.parse(created),
    )

    @Test fun viewModeKeyAndDefault() {
        assertEquals("communityCalendar.home.viewMode", HomeViewMode.STORAGE_KEY)
        assertEquals(HomeViewMode.Board, HomeViewMode.from(null))
        assertEquals(HomeViewMode.Calendar, HomeViewMode.from("calendar"))
    }

    @Test fun gridIsMondayFirst() {
        // 1 Nov 2026 is a Sunday → 6 leading blanks.
        val cells = HomeCalendarLogic.gridCells(YearMonth.of(2026, 11))
        assertEquals(6, cells.takeWhile { it == null }.size)
        assertEquals(LocalDate.of(2026, 11, 1), cells[6])
        assertEquals(36, cells.size)
        assertNull(HomeCalendarLogic.gridCells(YearMonth.of(2026, 12)).firstOrNull()?.takeIf { false })
    }

    @Test fun monthsStartAtCurrentMonth() {
        val months = HomeCalendarLogic.monthStarts(Instant.parse("2026-11-16T00:00:00Z"), 3, nz)
        assertEquals(listOf(YearMonth.of(2026, 11), YearMonth.of(2026, 12), YearMonth.of(2027, 1)), months)
    }

    @Test fun multiDayListingMarksEveryDayWithDistinctOrderedTopics() {
        // 20 Nov 09:00 NZ → 22 Nov 17:00 NZ
        val a = ev("a", "2026-11-19T20:00:00Z", "2026-11-22T04:00:00Z", topics = listOf(EventCategory.Sport, EventCategory.LiveMusic))
        val b = ev("b", "2026-11-20T20:00:00Z", "2026-11-20T22:00:00Z", cat = EventCategory.LiveMusic)
        val map = HomeCalendarLogic.topicsByDay(listOf(a, b), YearMonth.of(2026, 11), nz)
        assertEquals(listOf(EventCategory.LiveMusic, EventCategory.Sport), map[LocalDate.of(2026, 11, 20)])
        assertEquals(listOf(EventCategory.LiveMusic, EventCategory.Sport), map[LocalDate.of(2026, 11, 21)])
        assertEquals(listOf(EventCategory.LiveMusic, EventCategory.Sport), map[LocalDate.of(2026, 11, 22)])
        assertNull(map[LocalDate.of(2026, 11, 23)])
    }

    @Test fun dayOrderingBoostedFirstThenFirstListed() {
        val early = ev("early", "2026-11-20T20:00:00Z", "2026-11-20T22:00:00Z", created = "2026-11-01T00:00:00Z")
        val late = ev("late", "2026-11-20T19:00:00Z", "2026-11-20T22:00:00Z", created = "2026-11-05T00:00:00Z")
        val boosted = ev("boost", "2026-11-20T21:00:00Z", "2026-11-20T22:00:00Z", created = "2026-11-09T00:00:00Z", paid = true)
        val top = ev("top", "2026-11-20T21:00:00Z", "2026-11-20T22:00:00Z", created = "2026-11-10T00:00:00Z").applyingActivePromotion(2, null)
        val day = HomeCalendarLogic.dayEvents(listOf(late, early, boosted, top), LocalDate.of(2026, 11, 21), nz)
        assertEquals(listOf("top", "boost", "early", "late"), day.map { it.id })
    }

    @Test fun shownOnHomeUntilMidnightAfterEnd() {
        val e = ev("e", "2026-11-16T20:00:00Z", "2026-11-16T22:00:00Z") // 17 Nov NZ
        assertTrue(HomeCalendarLogic.isShownOnHome(e, Instant.parse("2026-11-17T10:00:00Z"), nz))
        assertFalse(HomeCalendarLogic.isShownOnHome(e, Instant.parse("2026-11-17T11:00:01Z"), nz))
        assertFalse(HomeCalendarLogic.isShownOnHome(ev("p", "2026-11-16T20:00:00Z", "2026-11-16T22:00:00Z", status = ListingStatus.PendingReview), Instant.parse("2026-11-16T00:00:00Z"), nz))
    }
}
