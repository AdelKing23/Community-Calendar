package com.atlasdigital.coastcalendar.data.model

import com.atlasdigital.coastcalendar.core.time.NzTime
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant

/** Row from the `public_events` view. Columns = iOS `publicEventSelect`. Timestamps stay as text and are parsed in [toLocalEvent]. */
@Serializable
data class PublicEventRecord(
    val id: String,
    val title: String,
    val category: String? = null,
    val town: String? = null,
    @SerialName("location_display_name") val locationDisplayName: String? = null,
    val venue: String? = null,
    @SerialName("start_at") val startAt: String,
    @SerialName("end_at") val endAt: String,
    @SerialName("price_label") val priceLabel: String? = null,
    @SerialName("is_free") val isFree: Boolean? = null,
    val audience: String? = null,
    @SerialName("short_description") val shortDescription: String? = null,
    @SerialName("long_description") val longDescription: String? = null,
    @SerialName("contact_name") val contactName: String? = null,
    @SerialName("contact_phone") val contactPhone: String? = null,
    @SerialName("contact_email") val contactEmail: String? = null,
    @SerialName("business_profile_id") val businessProfileId: String? = null,
    @SerialName("organisation_name") val organisationName: String? = null,
    @SerialName("is_featured") val isFeatured: Boolean? = null,
    @SerialName("is_paid_push") val isPaidPush: Boolean? = null,
    val status: String? = null,
    @SerialName("listing_kind") val listingKind: String? = null,
    @SerialName("poll_question") val pollQuestion: String? = null,
    @SerialName("poll_options") val pollOptions: List<String>? = null,
    @SerialName("poll_allows_custom_answer") val pollAllowsCustomAnswer: Boolean? = null,
    @SerialName("unverified_user_listing") val unverifiedUserListing: Boolean? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    @SerialName("is_all_day") val isAllDay: Boolean? = null,
) {
    fun toLocalEvent(topics: List<EventCategory> = emptyList()): LocalEvent? {
        val start = NzTime.parse(startAt) ?: return null
        val end = NzTime.parse(endAt) ?: return null
        val kind = ListingKind.from(listingKind)
        val poll = if (pollQuestion != null && !pollOptions.isNullOrEmpty()) {
            PollDetails.of(pollQuestion, pollOptions, pollAllowsCustomAnswer ?: false).takeIf { it.isValid }
        } else null
        return LocalEvent(
            id = id,
            title = title,
            category = EventCategory.from(category) ?: EventCategory.Community,
            topics = topics,
            town = CoastTown.from(town),
            locationDisplayName = locationDisplayName,
            venue = venue.orEmpty(),
            start = start,
            end = end,
            priceLabel = priceLabel ?: "Free",
            isFree = isFree ?: true,
            shortDescription = shortDescription.orEmpty(),
            longDescription = longDescription.orEmpty(),
            businessProfileId = businessProfileId,
            organisationName = organisationName,
            contactName = contactName,
            isFeatured = isFeatured ?: false,
            isPaidPush = isPaidPush ?: false,
            status = ListingStatus.from(status),
            kind = kind,
            pollDetails = poll,
            isAllDay = isAllDay ?: false,
            createdAt = NzTime.parse(createdAt) ?: Instant.EPOCH,
            audience = audience.orEmpty(),
            contactEmail = contactEmail,
            contactPhone = contactPhone,
        )
    }

    companion object {
        /** Exactly iOS `SupabaseEventService.publicEventSelect`. */
        val SELECT: String = listOf(
            "id", "title", "category", "town", "location_display_name", "venue", "start_at", "end_at",
            "price_label", "is_free", "audience", "short_description", "long_description", "contact_name",
            "contact_phone", "contact_email", "business_profile_id", "organisation_name", "is_featured",
            "is_paid_push", "status", "listing_kind", "poll_question", "poll_options", "poll_allows_custom_answer",
            "unverified_user_listing", "created_at", "updated_at", "is_all_day",
        ).joinToString(",")
    }
}

@Serializable
data class EventTopicRow(
    @SerialName("event_id") val eventId: String,
    @SerialName("topic_slug") val topicSlug: String,
)

@Serializable
data class EventTopicInsert(
    @SerialName("event_id") val eventId: String,
    @SerialName("topic_slug") val topicSlug: String,
    val source: String = "user",
)

@Serializable
data class PublishedEventLocationTargetRow(
    @SerialName("event_id") val eventId: String,
    @SerialName("sort_order") val sortOrder: Int? = null,
)

@Serializable
data class LocationScopeRecord(
    val slug: String,
    val name: String,
    @SerialName("scope_type") val scopeType: String,
    val subtitle: String? = null,
    @SerialName("sort_priority") val sortPriority: Int = 1000,
)

@Serializable
data class LocationScopeEdgeRecord(
    @SerialName("child_slug") val childSlug: String,
    @SerialName("parent_slug") val parentSlug: String,
    @SerialName("relationship_type") val relationshipType: String,
    @SerialName("sort_order") val sortOrder: Int = 0,
)

@Serializable
data class InsertedId(val id: String)

@Serializable
data class WelcomeDismissalRow(
    @SerialName("user_id") val userId: String? = null,
    @SerialName("welcome_version") val welcomeVersion: Int,
)

/** iOS `MemberNoticeCreateRequest`: notices publish straight away (server applies the 14-day default expiry). */
@Serializable
data class MemberNoticeInsert(
    @SerialName("business_profile_id") val businessProfileId: String,
    @SerialName("owner_user_id") val ownerUserId: String,
    val title: String,
    val summary: String? = null,
    val body: String? = null,
    @SerialName("template_style") val templateStyle: String = "weekly_letter",
    val status: String = "published",
)

/** Row from `public_event_images` (iOS `publicEventImageSelect`). */
@Serializable
data class EventImageRecord(
    val id: String,
    @SerialName("event_id") val eventId: String,
    @SerialName("storage_path") val storagePath: String,
    val position: Int = 1,
    @SerialName("mime_type") val mimeType: String? = null,
    @SerialName("byte_size") val byteSize: Long? = null,
    val width: Int? = null,
    val height: Int? = null,
) {
    companion object {
        const val SELECT = "id,event_id,storage_path,position,mime_type,byte_size,width,height"
    }
}

/** iOS `EventImageInsert` into `event_images`. */
@Serializable
data class EventImageInsert(
    @SerialName("event_id") val eventId: String,
    @SerialName("storage_path") val storagePath: String,
    val position: Int,
    @SerialName("mime_type") val mimeType: String,
    @SerialName("byte_size") val byteSize: Int,
    val width: Int,
    val height: Int,
)

/** Row from `active_event_promotions` (iOS `SupabaseActiveEventPromotionRecord`). */
@Serializable
data class ActivePromotionRecord(
    @SerialName("event_id") val eventId: String,
    val tier: String? = null,
    val placement: String? = null,
    @SerialName("starts_at") val startsAt: String? = null,
    @SerialName("ends_at") val endsAt: String? = null,
    @SerialName("paid_at") val paidAt: String? = null,
    @SerialName("placement_rank") val placementRank: Int = 0,
) {
    /** iOS `sortsBefore`: higher rank first, then earliest paid. */
    fun sortsBefore(other: ActivePromotionRecord): Boolean {
        if (placementRank != other.placementRank) return placementRank > other.placementRank
        val l = NzTime.parse(paidAt) ?: Instant.MAX
        val r = NzTime.parse(other.paidAt) ?: Instant.MAX
        return l < r
    }
}

/** Row from `public_host_directory` (iOS `PublicBusinessProfileRecord`, `publicMemberProfileSelect`). */
@Serializable
data class PublicMemberProfileRecord(
    val id: String,
    @SerialName("public_slug") val publicSlug: String? = null,
    @SerialName("display_name") val displayName: String = "",
    @SerialName("area_scope_id") val areaScopeId: String? = null,
    val bio: String? = null,
    @SerialName("public_contact_name") val publicContactName: String? = null,
    @SerialName("public_contact_email") val publicContactEmail: String? = null,
    @SerialName("public_phone") val publicPhone: String? = null,
    @SerialName("public_location_text") val publicLocationText: String? = null,
    @SerialName("public_address") val publicAddress: String? = null,
    @SerialName("public_website") val publicWebsite: String? = null,
    @SerialName("avatar_image_path") val avatarImagePath: String? = null,
    @SerialName("hero_image_path") val heroImagePath: String? = null,
    @SerialName("published_at") val publishedAt: String? = null,
) {
    companion object {
        const val SELECT = "id,public_slug,display_name,area_scope_id,bio,public_contact_name,public_contact_email,public_phone," +
            "public_location_text,public_address,public_website,avatar_image_path,hero_image_path,avatar_image_position_x," +
            "avatar_image_position_y,hero_image_position_x,hero_image_position_y,published_at,public_contact_revision," +
            "public_contact_confirmed_revision,public_contact_confirmed_at"
    }
}
