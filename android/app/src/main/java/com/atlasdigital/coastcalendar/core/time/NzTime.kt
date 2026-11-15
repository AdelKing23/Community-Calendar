package com.atlasdigital.coastcalendar.core.time

import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

/** Time rules shared with iOS (`PendingEventInsert`, `NZDay`, `PollCloseWindow`) and web. */
object NzTime {
    val NZ: ZoneId = ZoneId.of("Pacific/Auckland")

    /** iOS/web `isoDateFormatter`: what PostgREST filters receive. */
    fun iso(instant: Instant): String = DateTimeFormatter.ISO_INSTANT.format(instant.truncatedTo(ChronoUnit.SECONDS))

    /** Postgres timestamptz text (e.g. 2026-11-17T11:00:00+00:00, fractional seconds allowed). */
    fun parse(value: String?): Instant? = value?.let { text ->
        runCatching { OffsetDateTime.parse(text).toInstant() }
            .recoverCatching { Instant.parse(text) }
            .getOrNull()
    }

    /** NZ midnight of the picked calendar day, and one second before the next NZ midnight (iOS `nzDayBounds`). */
    fun nzDayBounds(day: LocalDate): Pair<Instant, Instant> {
        val start = day.atStartOfDay(NZ).toInstant()
        val next = day.plusDays(1).atStartOfDay(NZ).toInstant()
        return start to next.minusSeconds(1)
    }

    /** yyyy-MM-dd, for the events.recurrence_until date column. */
    fun localDayString(day: LocalDate): String = day.toString()

    /**
     * Home rule (same as iOS and web Board): show until end, Finished until midnight.
     * iOS uses the device's start of today; Android does the same.
     */
    fun archiveCutoff(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Instant =
        now.atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()

    fun combine(day: LocalDate, time: LocalTime, zone: ZoneId = ZoneId.systemDefault()): Instant =
        day.atTime(time.withSecond(0).withNano(0)).atZone(zone).toInstant()

    val utc: ZoneOffset = ZoneOffset.UTC
}

/** Poll close limits shared with iOS and web (POLL_CLOSE_MIN_MS / POLL_CLOSE_MAX_DAYS): 1 hour to 90 days, default 7 days. */
object PollCloseWindow {
    const val MINIMUM_SECONDS: Long = 60 * 60
    const val MAXIMUM_DAYS: Long = 90
    const val DEFAULT_DAYS: Long = 7

    fun range(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): ClosedRange<Instant> {
        val earliest = now.plusSeconds(MINIMUM_SECONDS)
        val latest = now.atZone(zone).plusDays(MAXIMUM_DAYS).toInstant()
        return earliest..latest
    }

    fun defaultClose(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Instant =
        now.atZone(zone).plusDays(DEFAULT_DAYS).toInstant()

    fun clamp(close: Instant, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Instant {
        val window = range(now, zone)
        return minOf(maxOf(close, window.start), window.endInclusive)
    }
}
