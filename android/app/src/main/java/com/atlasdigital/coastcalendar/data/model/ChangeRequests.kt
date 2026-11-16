package com.atlasdigital.coastcalendar.data.model

import com.atlasdigital.coastcalendar.core.time.NzTime
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId

enum class EventChangeType(val raw: String, val supportTitle: String) {
    EditRequest("edit_request", "Edit request"), RemovalRequest("removal_request", "Removal request");

    companion object {
        fun from(raw: String?) = if (raw == "removal_request") RemovalRequest else EditRequest
    }
}

enum class EventChangeRequestStatus(val raw: String) {
    Pending("pending"), Approved("approved"), Rejected("rejected"), Cancelled("cancelled"), Applied("applied");

    companion object {
        fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: Pending
    }
}

/** iOS `EventReviewReason` (labels kept, payment-free). */
enum class EventReviewReason(val raw: String, val label: String) {
    ApprovedApplied("approved_applied", "Approved and applied"),
    NeedsPayment("needs_payment", "Needs member access"),
    InappropriateWording("inappropriate_wording", "Inappropriate wording"),
    InappropriateImage("inappropriate_image", "Inappropriate image"),
    WrongCategory("wrong_category", "Wrong category"),
    WrongDateTime("wrong_date_time", "Wrong date or time"),
    UnclearLocation("unclear_location", "Unclear location"),
    DuplicateListing("duplicate_listing", "Duplicate listing"),
    CommercialSubmittedAsFree("commercial_submitted_as_free", "Commercial submitted as free"),
    PromotionUpgradeRequired("promotion_upgrade_required", "Promotion upgrade required"),
    NotEnoughInformation("not_enough_information", "Not enough information"),
    Other("other", "Other");

    companion object {
        fun from(raw: String?): EventReviewReason? = entries.firstOrNull { it.raw == raw }
    }
}

/** Row from `event_change_requests` with the embedded event (`*,events(*,event_images(*))`). */
@Serializable
data class EventChangeRequestRecord(
    val id: String,
    @SerialName("event_id") val eventId: String,
    @SerialName("requested_by") val requestedBy: String,
    @SerialName("change_type") val changeType: String,
    val status: String,
    @SerialName("proposed_changes") val proposedChanges: JsonObject = JsonObject(emptyMap()),
    @SerialName("requester_note") val requesterNote: String? = null,
    @SerialName("review_reason") val reviewReason: String? = null,
    @SerialName("support_note") val supportNote: String? = null,
    @SerialName("reviewed_at") val reviewedAt: String? = null,
    @SerialName("applied_at") val appliedAt: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    val events: PublicEventRecord? = null,
) {
    val type: EventChangeType get() = EventChangeType.from(changeType)
    val requestStatus: EventChangeRequestStatus get() = EventChangeRequestStatus.from(status)
    val reason: EventReviewReason? get() = EventReviewReason.from(reviewReason)
    val created: Instant get() = NzTime.parse(createdAt) ?: Instant.EPOCH
    val isPending: Boolean get() = requestStatus == EventChangeRequestStatus.Pending

    /** iOS `userSummary`. */
    val userSummary: String
        get() {
            val r = reason?.label
            return when (requestStatus) {
                EventChangeRequestStatus.Pending -> "${type.supportTitle} pending review"
                EventChangeRequestStatus.Applied -> r?.let { "Applied: $it" } ?: "Applied"
                EventChangeRequestStatus.Approved -> r?.let { "Approved: $it" } ?: "Approved"
                EventChangeRequestStatus.Rejected -> r?.let { "Rejected: $it" } ?: "Rejected"
                EventChangeRequestStatus.Cancelled -> r?.let { "Cancelled: $it" } ?: "Cancelled"
            }
        }

    /** Proposed field → display text (iOS `EventChangeValue.displayText`). */
    fun proposedDisplay(): List<Pair<String, String>> = proposedChanges.map { (k, v) ->
        val prim = v as? JsonPrimitive
        val text = prim?.booleanOrNull?.let { if (it) "Yes" else "No" } ?: prim?.contentOrNull ?: v.toString()
        k to text
    }

    companion object {
        const val SELECT = "*,events(*,event_images(*))"
    }
}

/** iOS `EventChangeRequestInsert` (status always pending). */
@Serializable
data class EventChangeRequestInsert(
    @SerialName("event_id") val eventId: String,
    @SerialName("requested_by") val requestedBy: String,
    @SerialName("change_type") val changeType: String,
    val status: String = "pending",
    @SerialName("proposed_changes") val proposedChanges: Map<String, JsonElement>,
    @SerialName("requester_note") val requesterNote: String? = null,
)

/**
 * iOS `ListingEditDraft`. Keeps all-day listings all-day (t222), keeps the listing's length when the start moves,
 * and keeps a poll's opening time while clamping its close to 1 h – 90 d after opening.
 */
data class ListingEditDraft(
    val title: String,
    val category: EventCategory,
    val town: CoastTown,
    val venue: String,
    val date: LocalDate,
    val time: LocalTime,
    val priceLabel: String,
    val audience: String,
    val shortDescription: String,
    val longDescription: String,
    val contactName: String,
    val contactEmail: String,
    val contactPhone: String,
    val isPoll: Boolean,
    val originalStart: Instant,
    val originalEnd: Instant,
    val pollClosesAt: Instant,
    val hasTime: Boolean,
    val wasAllDay: Boolean,
) {
    val isAllDay: Boolean get() = !isPoll && !hasTime
    val canSubmit: Boolean get() = listOf(title, venue, shortDescription).all { it.isNotBlank() }

    fun startDate(zone: ZoneId = ZoneId.systemDefault()): Instant = when {
        isPoll -> originalStart
        isAllDay -> NzTime.nzDayBounds(date).first
        else -> date.atTime(time.withSecond(0).withNano(0)).atZone(zone).toInstant()
    }

    fun pollCloseRange(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): ClosedRange<Instant> {
        val upper = originalStart.atZone(zone).plusDays(com.atlasdigital.coastcalendar.core.time.PollCloseWindow.MAXIMUM_DAYS).toInstant()
        val lower = minOf(maxOf(originalStart.plusSeconds(com.atlasdigital.coastcalendar.core.time.PollCloseWindow.MINIMUM_SECONDS), now), upper)
        return lower..upper
    }

    fun endDate(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Instant {
        if (isPoll) {
            val r = pollCloseRange(now, zone)
            return minOf(maxOf(pollClosesAt, r.start), r.endInclusive)
        }
        if (isAllDay) return NzTime.nzDayBounds(date).second
        val length = if (wasAllDay) 0L else java.time.Duration.between(originalStart, originalEnd).seconds
        return startDate(zone).plusSeconds(if (length > 0) length else 2 * 60 * 60)
    }

    /** iOS `proposedChanges` (same keys and defaults). */
    fun proposedChanges(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Map<String, JsonElement> {
        val price = priceLabel.trim().ifEmpty { "Free" }
        val description = shortDescription.trim()
        val longText = longDescription.trim()
        return linkedMapOf(
            "title" to JsonPrimitive(title.trim()),
            "category" to JsonPrimitive(category.raw),
            "town" to JsonPrimitive(town.raw),
            "venue" to JsonPrimitive(venue.trim()),
            "start_at" to JsonPrimitive(NzTime.iso(startDate(zone))),
            "end_at" to JsonPrimitive(NzTime.iso(endDate(now, zone))),
            "is_all_day" to JsonPrimitive(isAllDay),
            "price_label" to JsonPrimitive(price),
            "is_free" to JsonPrimitive(price.contains("free", ignoreCase = true)),
            "audience" to JsonPrimitive(audience.trim().ifEmpty { "Everyone" }),
            "short_description" to JsonPrimitive(description),
            "long_description" to JsonPrimitive(longText.ifEmpty { description }),
            "contact_name" to JsonPrimitive(contactName.trim()),
            "contact_email" to JsonPrimitive(contactEmail.trim()),
            "contact_phone" to JsonPrimitive(contactPhone.trim()),
        )
    }

    companion object {
        private val NZ: ZoneId = ZoneId.of("Pacific/Auckland")

        fun from(event: LocalEvent, zone: ZoneId = ZoneId.systemDefault()): ListingEditDraft {
            // All-day listings start at NZ midnight: show that NZ day.
            val day = if (event.isAllDay) event.start.atZone(NZ).toLocalDate() else event.start.atZone(zone).toLocalDate()
            val time = if (event.isAllDay) LocalTime.NOON else event.start.atZone(zone).toLocalTime().withSecond(0).withNano(0)
            return ListingEditDraft(
                title = event.title, category = event.category, town = event.town, venue = event.venue, date = day, time = time,
                priceLabel = event.priceLabel, audience = event.audience, shortDescription = event.shortDescription,
                longDescription = event.longDescription, contactName = event.contactName.orEmpty(),
                contactEmail = event.contactEmail.orEmpty(), contactPhone = event.contactPhone.orEmpty(),
                isPoll = event.isPoll, originalStart = event.start, originalEnd = event.end, pollClosesAt = event.end,
                hasTime = !event.isAllDay, wasAllDay = event.isAllDay,
            )
        }
    }
}

/** iOS `ListingStatus.userLabel` / owner note (payment-free wording). */
object ListingStatusCopy {
    fun userLabel(status: ListingStatus): String = when (status) {
        ListingStatus.PendingReview -> "Pending"
        ListingStatus.ApprovedAwaitingPayment -> "Member Access"
        ListingStatus.Published -> "Published"
        ListingStatus.Rejected -> "Needs Work"
        ListingStatus.Archived -> "Archived"
        ListingStatus.OrgCalendar -> "Calendar"
    }

    fun ownerNote(status: ListingStatus): String = when (status) {
        ListingStatus.PendingReview -> "Pending review. You can remove it now; it will leave the public queue."
        ListingStatus.ApprovedAwaitingPayment -> "Approved. It goes public once your Organisation’s member access is active."
        ListingStatus.Published -> "Published. Future edits to price, date, venue, photos or promotion will return to review."
        ListingStatus.Rejected -> "Support did not approve this listing. Tap View to read notes, then Edit or Remove."
        ListingStatus.Archived -> "Archived listing."
        ListingStatus.OrgCalendar -> "Saved on the organisation calendar."
    }
}
