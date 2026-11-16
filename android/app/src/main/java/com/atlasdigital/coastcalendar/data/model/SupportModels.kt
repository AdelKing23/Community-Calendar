package com.atlasdigital.coastcalendar.data.model

import com.atlasdigital.coastcalendar.core.time.NzTime
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant


/** Contact Support topics (iOS `ContactSupportScreen.Topic` raw values; the payment topic is left out on Android). */
enum class SupportTopic(val raw: String) {
    Listing("Listing help"), Account("Account"), Safety("Safety or content"), Other("Other")
}

enum class SupportRequestStatus(val raw: String, val label: String) {
    Open("open", "Open"), InReview("in_review", "In review"), Closed("closed", "Closed");

    companion object {
        fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: Open
    }
}

/** Row from `support_requests` (iOS `SupportRequestRecord`). */
@Serializable
data class SupportRequestRecord(
    val id: String,
    @SerialName("submitted_by") val submittedBy: String? = null,
    val topic: String = "",
    @SerialName("listing_reference") val listingReference: String? = null,
    val message: String = "",
    val status: String = "open",
    @SerialName("support_note") val supportNote: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
) {
    val requestStatus: SupportRequestStatus get() = SupportRequestStatus.from(status)
    val created: Instant get() = NzTime.parse(createdAt) ?: Instant.EPOCH
}

/** iOS `EventReportStatus`. */
enum class EventReportStatus(val raw: String, val label: String, val sortPriority: Int) {
    Open("open", "Open", 0), InReview("in_review", "In review", 1), Closed("closed", "Closed", 2), Dismissed("dismissed", "Dismissed", 3);

    companion object {
        fun from(raw: String?) = entries.firstOrNull { it.raw == raw } ?: Open
    }
}

/** Row from `event_reports` with the embedded event (`*,events(*,event_images(*))`). */
@Serializable
data class EventReportRecord(
    val id: String,
    @SerialName("event_id") val eventId: String,
    @SerialName("reporter_user_id") val reporterUserId: String? = null,
    val category: String = "other",
    val details: String? = null,
    val status: String = "open",
    @SerialName("support_note") val supportNote: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    val events: PublicEventRecord? = null,
) {
    val reportStatus: EventReportStatus get() = EventReportStatus.from(status)
    val reportCategory: EventReportCategory get() = EventReportCategory.from(category)
    val created: Instant get() = NzTime.parse(createdAt) ?: Instant.EPOCH
}

/** iOS `BusinessProfileStatus.supportSortPriority` order: pending first. */
val BusinessProfileStatus.supportSortPriority: Int
    get() = when (this) {
        BusinessProfileStatus.PendingReview -> 0
        BusinessProfileStatus.Approved -> 1
        BusinessProfileStatus.Rejected -> 2
        BusinessProfileStatus.Suspended -> 3
        BusinessProfileStatus.Archived -> 4
    }

/** iOS `ListingStatus.supportLabel` (neutral wording for the member-access state). */
val ListingStatus.supportLabel: String
    get() = when (this) {
        ListingStatus.PendingReview -> "Pending"
        ListingStatus.ApprovedAwaitingPayment -> "Member Access"
        ListingStatus.Published -> "Published"
        ListingStatus.Rejected -> "Rejected"
        ListingStatus.Archived -> "Archived"
        ListingStatus.OrgCalendar -> "Calendar"
    }
