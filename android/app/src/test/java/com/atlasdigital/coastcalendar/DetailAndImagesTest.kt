package com.atlasdigital.coastcalendar

import com.atlasdigital.coastcalendar.core.calendar.CalendarInsert
import com.atlasdigital.coastcalendar.core.image.ListingPhotoCompressor
import com.atlasdigital.coastcalendar.data.model.ActivePromotionRecord
import com.atlasdigital.coastcalendar.data.model.CoastTown
import com.atlasdigital.coastcalendar.data.model.EventCategory
import com.atlasdigital.coastcalendar.data.model.EventReportCategory
import com.atlasdigital.coastcalendar.data.model.ListingImageStoragePath
import com.atlasdigital.coastcalendar.data.model.ListingKind
import com.atlasdigital.coastcalendar.data.model.ListingStatus
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.data.model.PollResponseCountRecord
import com.atlasdigital.coastcalendar.data.model.PollResults
import com.atlasdigital.coastcalendar.data.model.PollUserResponse
import com.atlasdigital.coastcalendar.data.repository.EventsRepository
import com.atlasdigital.coastcalendar.feature.detail.PollStatus
import com.atlasdigital.coastcalendar.feature.detail.PollUiState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class DetailAndImagesTest {
    private val nz = ZoneId.of("Pacific/Auckland")

    private fun event(start: String, end: String, allDay: Boolean) = LocalEvent(
        id = "e1", title = "Market", category = EventCategory.Markets, town = CoastTown.Beachlands, locationDisplayName = null,
        venue = "Hall", start = Instant.parse(start), end = Instant.parse(end), priceLabel = "Free", isFree = true,
        shortDescription = "Stalls", longDescription = "", businessProfileId = null, organisationName = "Org", contactName = null,
        isFeatured = false, isPaidPush = false, status = ListingStatus.Published, kind = ListingKind.Event, pollDetails = null,
        isAllDay = allDay, createdAt = Instant.EPOCH,
    )

    @Test fun storagePathMatchesIos() {
        assertEquals("abc/def/123.jpg", ListingImageStoragePath.make("ABC", "DEF", "123"))
        assertEquals("listing-images", ListingImageStoragePath.BUCKET)
        assertEquals(5, ListingImageStoragePath.MAX_PHOTOS)
    }

    @Test fun compressorTargetSizeCapsLongestSideAt1600() {
        assertEquals(1600 to 1200, ListingPhotoCompressor.targetSize(4000, 3000))
        assertEquals(900 to 1600, ListingPhotoCompressor.targetSize(1800, 3200))
        assertEquals(800 to 600, ListingPhotoCompressor.targetSize(800, 600))
    }

    @Test fun allDayCalendarInsertUsesUtcMidnightsForTheNzDay() {
        // 17 Nov 2026 NZ all-day = 16 Nov 11:00Z .. 17 Nov 10:59:59Z
        val insert = CalendarInsert.of(event("2026-11-16T11:00:00Z", "2026-11-17T10:59:59Z", allDay = true), nz)
        assertTrue(insert.allDay)
        assertEquals(Instant.parse("2026-11-17T00:00:00Z").toEpochMilli(), insert.beginMillis)
        assertEquals(Instant.parse("2026-11-18T00:00:00Z").toEpochMilli(), insert.endMillis)
        assertEquals("Hall, Beachlands", insert.location)
    }

    @Test fun timedCalendarInsertKeepsInstants() {
        val insert = CalendarInsert.of(event("2026-11-16T20:00:00Z", "2026-11-16T22:00:00Z", allDay = false), nz)
        assertFalse(insert.allDay)
        assertEquals(Instant.parse("2026-11-16T20:00:00Z").toEpochMilli(), insert.beginMillis)
    }

    @Test fun finishedOnceEnded() {
        val e = event("2026-11-16T20:00:00Z", "2026-11-16T22:00:00Z", allDay = false)
        assertFalse(e.isFinished(Instant.parse("2026-11-16T21:00:00Z")))
        assertTrue(e.isFinished(Instant.parse("2026-11-16T22:00:01Z")))
    }

    @Test fun bestPromotionIsHighestRankThenEarliestPaid() {
        val rows = listOf(
            ActivePromotionRecord("e1", placementRank = 1, paidAt = "2026-11-01T00:00:00Z"),
            ActivePromotionRecord("e1", placementRank = 2, paidAt = "2026-11-05T00:00:00Z"),
            ActivePromotionRecord("e1", placementRank = 2, paidAt = "2026-11-02T00:00:00Z"),
            ActivePromotionRecord("e2", placementRank = 1),
        )
        val best = EventsRepository.bestPromotionPerEvent(rows)
        assertEquals(2, best["e1"]!!.placementRank)
        assertEquals("2026-11-02T00:00:00Z", best["e1"]!!.paidAt)
        assertEquals(1, best["e2"]!!.placementRank)
        val promoted = event("2026-11-16T20:00:00Z", "2026-11-16T22:00:00Z", false).applyingActivePromotion(2, null)
        assertEquals("Top Boost", promoted.promotionBadgeTitle)
    }

    @Test fun pollStatusCopyMatchesIos() {
        val results = PollResults(listOf(PollResponseCountRecord("A", 2), PollResponseCountRecord("B", 1)))
        assertEquals("Be the first to answer.", PollStatus.text(false, PollUiState()))
        assertEquals("3 responses so far.", PollStatus.text(false, PollUiState(results = results)))
        assertEquals("Your answer: A.", PollStatus.text(false, PollUiState(selectedOption = "A")))
        assertEquals("Voting closed. Your answer: A.", PollStatus.text(true, PollUiState(selectedOption = "A")))
        assertEquals("Voting closed.", PollStatus.text(true, PollUiState()))
        assertEquals("Other", PollUserResponse(selectedOption = null, customAnswer = "mine").displayAnswer)
        assertTrue(PollUserResponse(selectedOption = null, customAnswer = "mine").isCustomAnswer)
    }

    @Test fun reportReasonsMatchIos() {
        assertEquals(
            listOf("wrong_or_outdated", "spam_or_scam", "unsafe_or_harmful", "inappropriate_content", "wrong_location", "other"),
            EventReportCategory.entries.map { it.raw },
        )
    }
}
