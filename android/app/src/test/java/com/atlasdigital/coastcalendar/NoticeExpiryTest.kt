package com.atlasdigital.coastcalendar

import com.atlasdigital.coastcalendar.data.model.NoticeExpiry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Duration
import java.time.Instant

class NoticeExpiryTest {
    private val now = Instant.parse("2026-11-16T03:00:00Z")

    @Test fun defaultIsFourteenDays() {
        assertEquals(14, NoticeExpiry.DEFAULT_DAYS)
        assertEquals(now.plus(Duration.ofDays(14)), NoticeExpiry.endsAt(NoticeExpiry.DEFAULT_DAYS, now))
    }

    @Test fun clampsToOneThroughNinety() {
        assertEquals(1, NoticeExpiry.clampDays(0))
        assertEquals(90, NoticeExpiry.clampDays(365))
        assertTrue(NoticeExpiry.endsAt(400, now) < now.plus(Duration.ofDays(90)))
    }

    @Test fun ninetyDaysStaysInsideServerCheck() {
        val end = NoticeExpiry.endsAt(90, now)
        // server: ends_at <= published_at + 90 days, published_at is set a moment after the client clock.
        assertTrue(end <= now.plus(Duration.ofDays(90)).minusSeconds(59))
        assertTrue(end > now.plus(Duration.ofDays(89)))
    }
}
