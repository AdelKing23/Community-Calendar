package com.atlasdigital.coastcalendar.data.model

import com.atlasdigital.coastcalendar.core.time.NzTime
import com.atlasdigital.coastcalendar.core.time.PollCloseWindow
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

/** What Create makes. Listing/Poll mirror iOS Create; Notice mirrors the iOS org-page notice (member_notices). */
enum class CreateKind(val label: String) { Listing("Listing"), Poll("Poll"), Notice("Notice") }

/** iOS `PendingListingDraft` (fields Create uses today). */
data class ListingDraft(
    val kind: ListingKind = ListingKind.Event,
    val title: String = "",
    val category: EventCategory = EventCategory.Community,
    val town: CoastTown = CoastTown.Beachlands,
    val locationScopeId: String = "beachlands",
    val locationDisplayName: String = "Beachlands",
    val venue: String = "",
    /** Start date is mandatory; it always has a value (defaults to today, like iOS). */
    val date: LocalDate = LocalDate.now(),
    val time: LocalTime = LocalTime.now().withSecond(0).withNano(0),
    /** t221: time is optional. Off = date-only listing (NZ midnight start, is_all_day). */
    val hasTime: Boolean = true,
    val priceLabel: String = "Free",
    val contactName: String = "",
    val contactEmail: String = "",
    val shortDescription: String = "",
    val pollQuestion: String = "",
    val pollOptions: List<String> = listOf("", ""),
    val allowsCustomPollAnswer: Boolean = false,
    val pollClosesAt: Instant = PollCloseWindow.defaultClose(),
    val recurrence: ListingRecurrence = ListingRecurrence.None,
    val hasRecurrenceEnd: Boolean = false,
    val recurrenceUntil: LocalDate = LocalDate.now().plusMonths(3),
) {
    val pollDetails: PollDetails?
        get() = if (pollQuestion.isBlank()) null else PollDetails.of(pollQuestion, pollOptions, allowsCustomPollAnswer)

    /** iOS `pollReviewText`, appended to long_description for Support review. */
    val pollReviewText: String?
        get() {
            val details = pollDetails ?: return null
            val options = details.options.mapIndexed { i, o -> "${i + 1}. $o" }.joinToString("\n")
            val custom = if (details.allowsCustomAnswer) "Allowed, max ${PollDetails.CUSTOM_ANSWER_LIMIT} characters" else "Not allowed"
            return "[POLL]\nQuestion: ${details.question}\n\nOptions:\n$options\n\nCustom answer: $custom\n[/POLL]"
        }

    /** iOS `validationResult`: names of the required fields still empty. */
    fun missingFields(): List<String> = buildList {
        if (title.isBlank()) add("title")
        when (kind) {
            ListingKind.Event -> {
                if (venue.isBlank()) add("venue")
                if (shortDescription.isBlank()) add("description")
            }
            ListingKind.Poll -> {
                if (pollQuestion.isBlank()) add("pollQuestion")
                if (pollOptions.count { it.isNotBlank() } < 2) add("pollOptions")
            }
        }
    }
}

/** Body POSTed to `events` (iOS `PendingEventInsert`). Nulls are omitted, like iOS encodeIfPresent. */
@Serializable
data class PendingEventInsert(
    val title: String,
    val category: String,
    val town: String,
    @SerialName("primary_location_scope_id") val primaryLocationScopeId: String? = null,
    @SerialName("location_display_name") val locationDisplayName: String? = null,
    val venue: String,
    @SerialName("start_at") val startAt: String,
    @SerialName("end_at") val endAt: String,
    @SerialName("price_label") val priceLabel: String,
    @SerialName("is_free") val isFree: Boolean,
    val audience: String,
    @SerialName("short_description") val shortDescription: String,
    @SerialName("long_description") val longDescription: String,
    @SerialName("contact_name") val contactName: String? = null,
    @SerialName("contact_email") val contactEmail: String? = null,
    @SerialName("business_profile_id") val businessProfileId: String,
    @SerialName("is_featured") val isFeatured: Boolean = false,
    @SerialName("is_paid_push") val isPaidPush: Boolean = false,
    @SerialName("unverified_user_listing") val unverifiedUserListing: Boolean = false,
    val status: String = ListingStatus.PendingReview.raw,
    @SerialName("listing_kind") val listingKind: String,
    @SerialName("poll_question") val pollQuestion: String? = null,
    @SerialName("poll_options") val pollOptions: List<String>? = null,
    @SerialName("poll_allows_custom_answer") val pollAllowsCustomAnswer: Boolean = false,
    @SerialName("recurrence_interval") val recurrenceInterval: String? = null,
    @SerialName("recurrence_until") val recurrenceUntil: String? = null,
    /** Only sent when true (iOS sends the key only for all-day listings). */
    @SerialName("is_all_day") val isAllDay: Boolean? = null,
) {
    companion object {
        private val UUID_REGEX = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")

        fun from(
            draft: ListingDraft,
            businessProfileId: String,
            now: Instant = Instant.now(),
            zone: ZoneId = ZoneId.systemDefault(),
        ): PendingEventInsert {
            val isPoll = draft.kind == ListingKind.Poll
            val start: Instant
            val end: Instant
            if (isPoll) {
                // Polls open on submit and close at the time chosen on Create (1 h – 90 d). end_at drives Finished/archive.
                start = now
                end = PollCloseWindow.clamp(draft.pollClosesAt, now, zone)
            } else if (draft.hasTime) {
                // Normal listings show until midnight at the end of the start date; end_at keeps a nominal 2 hours.
                start = NzTime.combine(draft.date, draft.time, zone)
                end = start.plusSeconds(2 * 60 * 60)
            } else {
                val bounds = NzTime.nzDayBounds(draft.date)
                start = bounds.first
                end = bounds.second
            }
            val isAllDay = !isPoll && !draft.hasTime
            val price = draft.priceLabel.trim()
            val short = draft.shortDescription.trim().ifEmpty { draft.pollDetails?.question ?: draft.title.trim() }
            val long = listOfNotNull(
                if (isPoll) "Listing kind: Poll" else null,
                short,
                draft.pollReviewText,
            ).filter { it.isNotEmpty() }.joinToString("\n\n")
            val repeats = if (draft.kind == ListingKind.Event) draft.recurrence else ListingRecurrence.None
            val poll = if (isPoll) draft.pollDetails else null
            return PendingEventInsert(
                title = draft.title.trim(),
                category = draft.category.raw,
                town = draft.town.raw,
                primaryLocationScopeId = draft.locationScopeId.takeIf { UUID_REGEX.matches(it) },
                locationDisplayName = draft.locationDisplayName.ifEmpty { null },
                venue = draft.venue.trim().ifEmpty { "Community poll in ${draft.locationDisplayName}" },
                startAt = NzTime.iso(start),
                endAt = NzTime.iso(end),
                priceLabel = price.ifEmpty { "Free" },
                isFree = price.isEmpty() || price.contains("free", ignoreCase = true),
                audience = "Everyone",
                shortDescription = short,
                longDescription = long,
                contactName = draft.contactName.trim().ifEmpty { null },
                contactEmail = draft.contactEmail.trim().ifEmpty { null },
                businessProfileId = businessProfileId,
                listingKind = draft.kind.raw,
                pollQuestion = poll?.question,
                pollOptions = poll?.options,
                pollAllowsCustomAnswer = poll?.allowsCustomAnswer ?: false,
                recurrenceInterval = repeats.databaseValue,
                recurrenceUntil = if (repeats == ListingRecurrence.None || !draft.hasRecurrenceEnd) null else NzTime.localDayString(draft.recurrenceUntil),
                isAllDay = if (isAllDay) true else null,
            )
        }
    }
}
