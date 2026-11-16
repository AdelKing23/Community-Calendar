package com.atlasdigital.coastcalendar

import com.atlasdigital.coastcalendar.core.reminders.ReminderLeadTime
import com.atlasdigital.coastcalendar.core.reminders.ReminderMath
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Duration
import java.time.Instant

class ReminderMathTest {
    private val now = Instant.parse("2026-11-16T03:00:00Z")

    @Test fun sameOffsetsAndDefaultAsIos() {
        assertEquals(listOf("atStart", "fiveMinutes", "fifteenMinutes", "thirtyMinutes", "oneHour", "twoHours", "oneDay", "oneWeek"),
            ReminderLeadTime.entries.map { it.raw })
        assertEquals(listOf(0L, 300, 900, 1800, 3600, 7200, 86400, 604800), ReminderLeadTime.entries.map { it.offset.seconds })
        assertEquals(ReminderLeadTime.OneHour, ReminderLeadTime.Default)
    }

    @Test fun firesAtStartMinusLead() {
        val start = now.plus(Duration.ofDays(3))
        assertEquals(start.minus(Duration.ofDays(1)), ReminderMath.triggerAt(start, ReminderLeadTime.OneDay, now))
    }

    @Test fun pastLeadFallsBackToOneMinuteButBeforeStart() {
        val start = now.plus(Duration.ofMinutes(10))
        assertEquals(now.plusSeconds(60), ReminderMath.triggerAt(start, ReminderLeadTime.OneHour, now))
        val soon = now.plusSeconds(75)
        assertEquals(soon.minusSeconds(30), ReminderMath.triggerAt(soon, ReminderLeadTime.OneHour, now))
    }

    @Test fun cannotScheduleWithinAMinute() {
        assertFalse(ReminderMath.canSchedule(now.plusSeconds(30), now))
        assertTrue(ReminderMath.canSchedule(now.plusSeconds(120), now))
    }
}
