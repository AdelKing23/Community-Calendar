package com.atlasdigital.coastcalendar.feature.home

import com.atlasdigital.coastcalendar.data.model.EventCategory
import com.atlasdigital.coastcalendar.data.model.ListingStatus
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId

enum class HomeViewMode(val raw: String) {
    Board("board"), Calendar("calendar");

    companion object {
        const val STORAGE_KEY = "communityCalendar.home.viewMode"
        fun from(raw: String?): HomeViewMode = entries.firstOrNull { it.raw == raw } ?: Board
    }
}

/** iOS `HomeCalendarLogic` (Monday-first, device zone). Pure, so it is unit tested. */
object HomeCalendarLogic {
    const val INITIAL_MONTH_COUNT = 3
    const val MONTHS_PER_LOAD = 2
    const val MAXIMUM_MONTH_COUNT = 18
    const val MAXIMUM_VISIBLE_DOTS = 4

    fun monthStarts(now: Instant, count: Int, zone: ZoneId): List<YearMonth> {
        val first = YearMonth.from(now.atZone(zone))
        return (0 until count.coerceAtLeast(0)).map { first.plusMonths(it.toLong()) }
    }

    /** Leading nulls so the 1st sits under its weekday (Monday first). */
    fun gridCells(month: YearMonth): List<LocalDate?> {
        val first = month.atDay(1)
        val padding = (first.dayOfWeek.value - DayOfWeek.MONDAY.value + 7) % 7
        return List(padding) { null } + (1..month.lengthOfMonth()).map { month.atDay(it) }
    }

    /** DateScope.today overlap rule: start < endOfDay && max(end, start) >= startOfDay. */
    fun overlaps(event: LocalEvent, day: LocalDate, zone: ZoneId): Boolean {
        val start = day.atStartOfDay(zone).toInstant()
        val end = day.plusDays(1).atStartOfDay(zone).toInstant()
        return event.start < end && maxOf(event.end, event.start) >= start
    }

    fun topics(event: LocalEvent): List<EventCategory> = event.topics.ifEmpty { listOf(event.category) }

    /** Distinct topics per day in EventCategory order; multi-day listings mark every day they overlap. */
    fun topicsByDay(events: List<LocalEvent>, month: YearMonth, zone: ZoneId): Map<LocalDate, List<EventCategory>> {
        val monthStart = month.atDay(1)
        val monthEnd = month.plusMonths(1).atDay(1)
        val sets = HashMap<LocalDate, MutableSet<EventCategory>>()
        for (event in events) {
            val firstDay = maxOf(event.start.atZone(zone).toLocalDate(), monthStart)
            var day = firstDay
            val eventTopics = topics(event)
            while (day < monthEnd && overlaps(event, day, zone)) {
                sets.getOrPut(day) { mutableSetOf() }.addAll(eventTopics)
                day = day.plusDays(1)
            }
        }
        return sets.mapValues { (_, set) -> EventCategory.entries.filter { it in set } }
    }

    fun isBoosted(event: LocalEvent): Boolean = event.effectivePromotionRank > 0

    /** Day order agreed with Isaac: boosted first, higher tier first, then first listed, then start. */
    val dayOrdering: Comparator<LocalEvent> = Comparator { l, r ->
        val lb = isBoosted(l)
        val rb = isBoosted(r)
        when {
            lb != rb -> if (lb) -1 else 1
            lb && l.effectivePromotionRank != r.effectivePromotionRank -> r.effectivePromotionRank.compareTo(l.effectivePromotionRank)
            l.createdAt != r.createdAt -> l.createdAt.compareTo(r.createdAt)
            else -> l.start.compareTo(r.start)
        }
    }

    fun dayEvents(events: List<LocalEvent>, day: LocalDate, zone: ZoneId): List<LocalEvent> =
        events.filter { overlaps(it, day, zone) }.sortedWith(dayOrdering)

    /** Published listings show until midnight at the end of their end date. */
    fun isShownOnHome(event: LocalEvent, now: Instant, zone: ZoneId): Boolean {
        if (event.status != ListingStatus.Published) return false
        val end = maxOf(event.end, event.start)
        val archiveAt = end.atZone(zone).toLocalDate().plusDays(1).atStartOfDay(zone).toInstant()
        return now < archiveAt
    }
}
