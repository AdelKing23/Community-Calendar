package com.atlasdigital.coastcalendar

import com.atlasdigital.coastcalendar.data.model.EventCategory
import com.atlasdigital.coastcalendar.data.model.ListingDraft
import com.atlasdigital.coastcalendar.data.model.ListingKind
import com.atlasdigital.coastcalendar.data.model.ListingRecurrence
import com.atlasdigital.coastcalendar.data.model.PendingEventInsert
import com.atlasdigital.coastcalendar.data.remote.SupabaseProvider
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

class PendingEventInsertTest {
    private val nz = ZoneId.of("Pacific/Auckland")
    private val now = Instant.parse("2026-11-16T00:00:00Z") // 13:00 NZDT

    private fun base() = ListingDraft(
        title = " Market day ", category = EventCategory.Markets, venue = "Hall", shortDescription = "Stalls",
        date = LocalDate.of(2026, 11, 21), time = LocalTime.of(9, 30),
    )

    @Test fun timedListingStartsAtChosenTimeWithNominalTwoHours() {
        val insert = PendingEventInsert.from(base(), "p1", now, nz)
        assertEquals("2026-11-20T20:30:00Z", insert.startAt)
        assertEquals("2026-11-20T22:30:00Z", insert.endAt)
        assertNull(insert.isAllDay)
        assertEquals("Market day", insert.title)
        assertEquals("pending_review", insert.status)
        assertEquals("event", insert.listingKind)
        assertEquals("Everyone", insert.audience)
        assertTrue(insert.isFree)
    }

    @Test fun dateOnlyListingIsAllDayNzMidnightToJustBeforeNextMidnight() {
        val insert = PendingEventInsert.from(base().copy(hasTime = false), "p1", now, nz)
        assertEquals("2026-11-20T11:00:00Z", insert.startAt)
        assertEquals("2026-11-21T10:59:59Z", insert.endAt)
        assertEquals(true, insert.isAllDay)
    }

    @Test fun allDayKeyOmittedUnlessTrueAndNullsOmitted() {
        val json = SupabaseProvider.json
        val timed = json.encodeToJsonElement(PendingEventInsert.serializer(), PendingEventInsert.from(base(), "p1", now, nz)).jsonObject
        assertFalse("is_all_day" in timed)
        assertFalse("recurrence_interval" in timed)
        assertFalse("primary_location_scope_id" in timed)
        val allDay = json.encodeToJsonElement(PendingEventInsert.serializer(), PendingEventInsert.from(base().copy(hasTime = false), "p1", now, nz)).jsonObject
        assertTrue("is_all_day" in allDay)
    }

    @Test fun pollOpensNowAndCloseIsClampedToOneHourMinimum() {
        val draft = base().copy(kind = ListingKind.Poll, pollQuestion = "Best day?", pollOptions = listOf("Sat", "Sun", ""), pollClosesAt = now.plusSeconds(60))
        val insert = PendingEventInsert.from(draft, "p1", now, nz)
        assertEquals("2026-11-16T00:00:00Z", insert.startAt)
        assertEquals("2026-11-16T01:00:00Z", insert.endAt)
        assertEquals(listOf("Sat", "Sun"), insert.pollOptions)
        assertNull(insert.isAllDay)
        assertTrue(insert.longDescription.startsWith("Listing kind: Poll"))
        assertTrue(insert.longDescription.contains("[POLL]"))
    }

    @Test fun pollCloseIsClampedToNinetyDaysMaximum() {
        val draft = base().copy(kind = ListingKind.Poll, pollQuestion = "Q", pollOptions = listOf("A", "B"), pollClosesAt = now.plusSeconds(200L * 86400))
        val insert = PendingEventInsert.from(draft, "p1", now, nz)
        assertEquals(now.atZone(nz).plusDays(90).toInstant().toString(), insert.endAt)
    }

    @Test fun recurrenceSentOnlyForListingsWithOptionalEndDate() {
        val weekly = PendingEventInsert.from(base().copy(recurrence = ListingRecurrence.Fortnightly), "p1", now, nz)
        assertEquals("fortnightly", weekly.recurrenceInterval)
        assertNull(weekly.recurrenceUntil)
        val ending = PendingEventInsert.from(base().copy(recurrence = ListingRecurrence.Monthly, hasRecurrenceEnd = true, recurrenceUntil = LocalDate.of(2027, 2, 28)), "p1", now, nz)
        assertEquals("2027-02-28", ending.recurrenceUntil)
        val poll = PendingEventInsert.from(base().copy(kind = ListingKind.Poll, pollQuestion = "Q", pollOptions = listOf("A", "B"), recurrence = ListingRecurrence.Weekly), "p1", now, nz)
        assertNull(poll.recurrenceInterval)
    }

    @Test fun slugIsNotSentAsPrimaryScopeIdButUuidIs() {
        assertNull(PendingEventInsert.from(base(), "p1", now, nz).primaryLocationScopeId)
        val uuid = "3f2b6c1e-8a4d-4c55-9a77-0d1e2f3a4b5c"
        assertEquals(uuid, PendingEventInsert.from(base().copy(locationScopeId = uuid), "p1", now, nz).primaryLocationScopeId)
    }

    @Test fun requiredFieldsMatchIos() {
        assertEquals(listOf("title", "venue", "description"), ListingDraft().missingFields())
        assertEquals(listOf("title", "pollQuestion", "pollOptions"), ListingDraft(kind = ListingKind.Poll).missingFields())
    }
}
