package com.atlasdigital.coastcalendar.data.model

import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields
import java.util.Locale

/** iOS `CoastTown`. Raw values are what `events.town` stores. */
enum class CoastTown(val raw: String) {
    All("All Areas"), Omana("Omana"), Whitford("Whitford"), Maraetai("Maraetai"), Beachlands("Beachlands"),
    Clevedon("Clevedon"), KawakawaBay("Kawakawa Bay"), OrerePoint("Orere Point"), Hunua("Hunua"), Ardmore("Ardmore");

    companion object {
        fun from(raw: String?): CoastTown = entries.firstOrNull { it.raw == raw } ?: All

        /** iOS `LocationScope.primaryTown` for the local ladder slugs. */
        fun forScopeSlug(slug: String): CoastTown = when (slug) {
            "omana" -> Omana
            "beachlands" -> Beachlands
            "maraetai" -> Maraetai
            "whitford" -> Whitford
            "clevedon" -> Clevedon
            "kawakawa-bay" -> KawakawaBay
            "orere-point" -> OrerePoint
            "hunua" -> Hunua
            "ardmore" -> Ardmore
            else -> All
        }
    }
}

/** iOS `EventCategory`. Raw values are stored in `events.category` and `event_topics.topic_slug`. */
enum class EventCategory(val raw: String, val shortLabel: String) {
    LiveMusic("Live Music", "Live Music"),
    FoodDrink("Food & Drink", "Food"),
    Markets("Markets", "Markets"),
    KidsFamily("Kids & Family", "Family"),
    Sport("Sport", "Sport"),
    Community("Community", "Community"),
    Fundraisers("Fundraisers", "Fundraisers"),
    ClassesWorkshops("Classes & Workshops", "Workshops"),
    Seniors("Seniors", "Seniors"),
    ChurchMaraeCultural("Church / Marae / Cultural", "Culture"),
    Nightlife("Nightlife", "Nightlife"),
    PublicNotices("Public Notices", "Notices");

    companion object {
        fun from(raw: String?): EventCategory? = entries.firstOrNull { it.raw == raw }
    }
}

enum class ListingStatus(val raw: String) {
    PendingReview("pending_review"), ApprovedAwaitingPayment("approved_awaiting_payment"), Published("published"),
    Rejected("rejected"), Archived("archived"), OrgCalendar("org_calendar");

    companion object {
        fun from(raw: String?): ListingStatus = entries.firstOrNull { it.raw == raw } ?: PendingReview
    }
}

enum class ListingKind(val raw: String, val label: String) {
    Event("event", "Listing"), Poll("poll", "Poll");

    companion object {
        fun from(raw: String?): ListingKind = if (raw == "poll") Poll else Event
    }
}

/** Repeat choice on Create. One listing creates the whole series and uses one listing from the allowance. */
enum class ListingRecurrence(val label: String) {
    None("Doesn’t repeat"), Weekly("Weekly"), Fortnightly("Fortnightly"), Monthly("Monthly"), Yearly("Yearly");

    /** Value stored in events.recurrence_interval (null = one-off). Same as iOS rawValue. */
    val databaseValue: String? get() = if (this == None) null else name.lowercase()
}

data class PollDetails(val question: String, val options: List<String>, val allowsCustomAnswer: Boolean) {
    val isValid: Boolean get() = question.isNotBlank() && options.count { it.isNotBlank() } >= 2

    companion object {
        const val MAX_OPTIONS = 10
        const val CUSTOM_ANSWER_LIMIT = 250

        fun of(question: String, options: List<String>, allowsCustomAnswer: Boolean) = PollDetails(
            question = question.trim(),
            options = options.map { it.trim() }.filter { it.isNotEmpty() }.take(MAX_OPTIONS),
            allowsCustomAnswer = allowsCustomAnswer,
        )

        /** iOS `strippedReviewBlock`: hide the [POLL] review block from public text. */
        fun strippedReviewBlock(text: String): String {
            val start = text.indexOf("[POLL]")
            val end = if (start >= 0) text.indexOf("[/POLL]", start) else -1
            if (start < 0 || end < 0) return text
            return (text.substring(0, start) + text.substring(end + "[/POLL]".length))
                .lines()
                .filter { it.trim() != "Listing kind: Poll" }
                .joinToString("\n")
                .trim()
        }
    }
}

/** iOS `LocalEvent` (subset needed by Home, What's On and cards). */
data class LocalEvent(
    val id: String,
    val title: String,
    val category: EventCategory,
    val topics: List<EventCategory> = emptyList(),
    val town: CoastTown,
    val locationDisplayName: String?,
    val venue: String,
    val start: Instant,
    val end: Instant,
    val priceLabel: String,
    val isFree: Boolean,
    val shortDescription: String,
    val longDescription: String,
    val businessProfileId: String?,
    val organisationName: String?,
    val contactName: String?,
    val isFeatured: Boolean,
    val isPaidPush: Boolean,
    val status: ListingStatus,
    val kind: ListingKind,
    val pollDetails: PollDetails?,
    val isAllDay: Boolean,
    val createdAt: Instant,
    val activePromotionRank: Int = 0,
    val activePromotionPaidAt: Instant? = null,
) {
    val isPubliclyVisible: Boolean get() = status == ListingStatus.Published
    val isPoll: Boolean get() = kind == ListingKind.Poll || pollDetails != null || longDescription.contains("[POLL]")
    val publicLongDescription: String get() = PollDetails.strippedReviewBlock(longDescription)

    val effectivePromotionRank: Int get() = maxOf(activePromotionRank, if (isPaidPush) PROMO_TOP_TEN else 0)
    val isPromoted: Boolean get() = effectivePromotionRank > 0
    val promotionBadgeTitle: String
        get() = when {
            effectivePromotionRank >= PROMO_PRIORITY_FIRST -> "Top Boost"
            effectivePromotionRank >= PROMO_TOP_TEN -> "Boosted"
            else -> "Featured"
        }

    val displayLocationName: String
        get() = locationDisplayName?.trim()?.takeIf { it.isNotEmpty() } ?: town.raw

    val organiserDisplayName: String
        get() = organisationName?.trim()?.takeIf { it.isNotEmpty() }
            ?: contactName?.trim()?.takeIf { it.isNotEmpty() }
            ?: "Organisation"

    fun matches(topic: EventCategory?): Boolean {
        if (topic == null) return true
        if (topics.isEmpty()) return category == topic
        return topic in topics
    }

    fun dateText(zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String =
        DATE_FORMAT.withLocale(locale).format(start.atZone(zone))

    fun timeText(zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String {
        if (isAllDay) return "All day"
        val f = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale)
        return "${f.format(start.atZone(zone))} – ${f.format(end.atZone(zone))}"
    }

    companion object {
        const val PROMO_TOP_TEN = 1
        const val PROMO_PRIORITY_FIRST = 2
        private val DATE_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("EEEE d MMMM yyyy")
    }
}

/** iOS `EventFeedOrdering`. */
object EventFeedOrdering {
    /** What's On order: promotion, paid-first, featured, then soonest start. */
    val discovery: Comparator<LocalEvent> = Comparator { l, r ->
        when {
            l.effectivePromotionRank != r.effectivePromotionRank -> r.effectivePromotionRank.compareTo(l.effectivePromotionRank)
            l.effectivePromotionRank >= LocalEvent.PROMO_PRIORITY_FIRST && l.activePromotionPaidAt != r.activePromotionPaidAt ->
                (l.activePromotionPaidAt ?: Instant.MAX).compareTo(r.activePromotionPaidAt ?: Instant.MAX)
            l.isFeatured != r.isFeatured -> if (l.isFeatured) -1 else 1
            else -> l.start.compareTo(r.start)
        }
    }

    /** Home board order: promotion, paid-first, featured, newest created, then latest start. */
    val board: Comparator<LocalEvent> = Comparator { l, r ->
        when {
            l.effectivePromotionRank != r.effectivePromotionRank -> r.effectivePromotionRank.compareTo(l.effectivePromotionRank)
            l.effectivePromotionRank >= LocalEvent.PROMO_PRIORITY_FIRST && l.activePromotionPaidAt != r.activePromotionPaidAt ->
                (l.activePromotionPaidAt ?: Instant.MAX).compareTo(r.activePromotionPaidAt ?: Instant.MAX)
            l.isFeatured != r.isFeatured -> if (l.isFeatured) -1 else 1
            l.createdAt != r.createdAt -> r.createdAt.compareTo(l.createdAt)
            else -> r.start.compareTo(l.start)
        }
    }
}

/** iOS `DateScope` (What's On tabs). */
enum class DateScope(val label: String, val chipLabel: String) {
    Today("Today", "Today"), ThisWeek("This Week", "Week"), ThisMonth("This Month", "Month"), Upcoming("Upcoming", "Upcoming");

    fun matches(event: LocalEvent, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): Boolean {
        val today = now.atZone(zone).toLocalDate()
        return when (this) {
            Today -> {
                val start = today.atStartOfDay(zone).toInstant()
                val end = today.plusDays(1).atStartOfDay(zone).toInstant()
                event.start < end && event.end >= start
            }
            ThisWeek -> {
                val firstDay: DayOfWeek = WeekFields.of(locale).firstDayOfWeek
                val weekStart = today.with(TemporalAdjusters.previousOrSame(firstDay)).atStartOfDay(zone).toInstant()
                val weekEnd = today.with(TemporalAdjusters.previousOrSame(firstDay)).plusDays(7).atStartOfDay(zone).toInstant()
                event.start < weekEnd && event.end >= weekStart
            }
            ThisMonth -> {
                val monthStart = today.withDayOfMonth(1)
                val start = monthStart.atStartOfDay(zone).toInstant()
                val end = monthStart.plusMonths(1).atStartOfDay(zone).toInstant()
                event.start < end && event.end >= start
            }
            Upcoming -> {
                val horizon = now.atZone(zone).plusDays(90).toInstant()
                event.end >= now && event.start <= horizon
            }
        }
    }
}
