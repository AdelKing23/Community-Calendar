package com.atlasdigital.coastcalendar.data.model

import com.atlasdigital.coastcalendar.core.time.NzTime
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant

/** iOS `BusinessOrganisationType`. */
enum class OrganisationType(val raw: String, val title: String) {
    Business("business", "Business"),
    SchoolEce("school_ece", "School/ECE"),
    SportsClub("sports_club", "Sports club"),
    CommunityGroup("community_group", "Community group"),
    CharityNonProfit("charity_non_profit", "Charity/non-profit"),
    Marae("marae_cultural_organisation", "Marae/cultural organisation"),
    Church("church_faith_community", "Church/faith community"),
    Market("market", "Market"),
    Hospitality("hospitality_venue", "Hospitality/venue"),
    Instructor("instructor_activity_provider", "Instructor/activity provider"),
    Council("council_public_service", "Council/public service"),
    Other("other_organisation", "Other organisation");

    companion object {
        fun from(raw: String?) = entries.firstOrNull { it.raw == raw }
    }
}

/** iOS `MembershipContactEmailValidator.isUsable`. */
object ContactEmailValidator {
    fun isUsable(email: String): Boolean {
        val v = email.trim()
        if (v.isEmpty() || v.any { it.isWhitespace() }) return false
        val parts = v.split("@")
        if (parts.size != 2) return false
        val (local, domain) = parts
        if (local.isEmpty() || domain.isEmpty()) return false
        val labels = domain.split(".")
        return labels.size >= 2 && labels.all { it.isNotEmpty() }
    }
}

/**
 * iOS `BusinessProfileDraft` → `save_my_business_profile` params (iOS `BusinessProfileSaveRequest`).
 * The plan id keeps the iOS default `local_business`; images are not edited on Android yet (existing values are kept).
 */
data class OrganisationDraft(
    val name: String = "",
    val type: OrganisationType? = null,
    val contactName: String = "",
    val email: String = "",
    val phone: String = "",
    val address: String = "",
    val website: String = "",
    val about: String = "",
    val areaScopeId: String = LocationScope.DEFAULT_ID,
    val selectedPlanId: String = "local_business",
    val heroImageUrl: String = "",
    val avatarImageUrl: String = "",
    val imagePositions: List<Double> = listOf(50.0, 50.0, 50.0, 50.0),
) {
    val canSubmit: Boolean
        get() = name.isNotBlank() && type != null && ContactEmailValidator.isUsable(email) && contactName.isNotBlank()

    fun rpcParams(): Map<String, Any?> = linkedMapOf(
        "p_business_name" to name.trim(),
        "p_organisation_type" to type?.raw,
        "p_contact_name" to contactName.trim().ifEmpty { null },
        "p_contact_email" to email.trim(),
        "p_phone" to phone.trim().ifEmpty { null },
        "p_address" to address.trim().ifEmpty { null },
        "p_website" to website.trim().ifEmpty { null },
        "p_about" to about.trim().ifEmpty { null },
        "p_area_scope_id" to areaScopeId,
        "p_selected_plan_id" to selectedPlanId,
        "p_hero_image_url" to heroImageUrl.trim().ifEmpty { null },
        "p_avatar_image_url" to avatarImageUrl.trim().ifEmpty { null },
        "p_hero_image_position_x" to imagePositions[0],
        "p_hero_image_position_y" to imagePositions[1],
        "p_avatar_image_position_x" to imagePositions[2],
        "p_avatar_image_position_y" to imagePositions[3],
    )

    companion object {
        fun from(p: BusinessProfileRecord) = OrganisationDraft(
            name = p.businessName,
            type = OrganisationType.from(p.organisationType),
            contactName = p.contactName.orEmpty(),
            email = p.contactEmail.orEmpty(),
            phone = p.phone.orEmpty(),
            address = p.address.orEmpty(),
            website = p.website.orEmpty(),
            about = p.about.orEmpty(),
            areaScopeId = p.areaScopeId ?: LocationScope.DEFAULT_ID,
            selectedPlanId = p.selectedPlanId ?: "local_business",
            heroImageUrl = p.heroImageUrl.orEmpty(),
            avatarImageUrl = p.avatarImageUrl.orEmpty(),
            imagePositions = listOf(p.heroImagePositionX, p.heroImagePositionY, p.avatarImagePositionX, p.avatarImagePositionY),
        )
    }
}

/** Neutral status copy for the owner's Organisation (no payment wording on Android). */
object OrganisationStatusCopy {
    fun title(state: BusinessAccountState): String = when (state.profile?.memberStatus) {
        null -> "Register your Organisation"
        BusinessProfileStatus.PendingReview -> "Application with Support"
        BusinessProfileStatus.Approved -> if (state.canSubmitAsOrganisation) "Organisation active" else "Approved"
        BusinessProfileStatus.Rejected -> "Changes needed"
        BusinessProfileStatus.Suspended -> "Organisation paused"
        BusinessProfileStatus.Archived -> "Organisation archived"
    }

    fun message(state: BusinessAccountState): String {
        val p = state.profile ?: return "Schools, clubs, venues and groups can apply for an Organisation page. Support reviews each application."
        return when (p.memberStatus) {
            BusinessProfileStatus.PendingReview -> "Support is reviewing ${p.businessName}. You can update the details while you wait."
            BusinessProfileStatus.Approved -> if (state.canSubmitAsOrganisation) "${p.businessName} can publish listings and Notices."
                else "${p.businessName} is approved. Listings go public once your Organisation’s member access is active."
            BusinessProfileStatus.Rejected -> p.rejectionReason?.takeIf { it.isNotBlank() } ?: "Support asked for changes. Update the details and send again."
            BusinessProfileStatus.Suspended -> p.suspensionReason?.takeIf { it.isNotBlank() } ?: "Contact Support about this Organisation."
            BusinessProfileStatus.Archived -> "Contact Support to restore this Organisation."
        }
    }
}

/** Row from `member_notices` (iOS `MemberNoticeRecord`). */
@Serializable
data class MemberNoticeRecord(
    val id: String,
    @SerialName("business_profile_id") val businessProfileId: String,
    @SerialName("owner_user_id") val ownerUserId: String,
    val title: String,
    val summary: String? = null,
    val body: String? = null,
    @SerialName("template_style") val templateStyle: String = "weekly_letter",
    val status: String = "published",
    @SerialName("hero_image_url") val heroImageUrl: String? = null,
    @SerialName("published_at") val publishedAt: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    @SerialName("ends_at") val endsAt: String? = null,
) {
    val endsInstant: Instant? get() = NzTime.parse(endsAt)
    fun hasEnded(now: Instant = Instant.now()): Boolean = endsInstant?.let { it <= now } ?: false
    val displayDate: Instant get() = NzTime.parse(publishedAt) ?: NzTime.parse(createdAt) ?: Instant.EPOCH

    companion object {
        const val SELECT = "id,business_profile_id,owner_user_id,title,summary,body,template_style,status,hero_image_url,published_at,created_at,updated_at,ends_at"
    }
}

@Serializable
data class MemberFollowUpsert(
    @SerialName("user_id") val userId: String,
    @SerialName("business_profile_id") val businessProfileId: String,
    @SerialName("notification_level") val notificationLevel: String = "all",
)

@Serializable
data class NoticeReadInsert(
    @SerialName("notice_id") val noticeId: String,
    @SerialName("user_id") val userId: String,
)

/** iOS `HostDirectoryItem` (profile-backed hosts only; Android has no owner fallback rows yet). */
data class HostDirectoryItem(val profile: PublicMemberProfileRecord, val events: List<LocalEvent>) {
    val name: String get() = profile.displayName.ifBlank { "Organisation" }
    val pollCount: Int get() = events.count { it.isPoll }
    val nextEvent: LocalEvent? get() = events.minByOrNull { it.start }
    val subtitle: String
        get() = profile.bio?.trim()?.takeIf { it.isNotEmpty() } ?: nextEvent?.let { "Next up: ${it.title}" } ?: "Verified organisation"
    val activityRank: Int get() = 12 + minOf(events.size, 8) * 10 + minOf(pollCount, 4) * 4

    companion object {
        val recommended: Comparator<HostDirectoryItem> =
            compareByDescending<HostDirectoryItem> { it.activityRank }
                .thenBy { it.nextEvent?.start ?: Instant.MAX }
                .thenBy(String.CASE_INSENSITIVE_ORDER) { it.name }

        fun build(profiles: List<PublicMemberProfileRecord>, events: List<LocalEvent>): List<HostDirectoryItem> {
            val byProfile = events.filter { it.businessProfileId != null }.groupBy { it.businessProfileId!!.lowercase() }
            return profiles.map { p -> HostDirectoryItem(p, byProfile[p.id.lowercase()].orEmpty().sortedBy { it.start }) }
        }
    }
}

/** Locked rule: Notices run 14 days by default, the owner can choose 1–90 days (server check ≤ publish + 90 days). */
object NoticeExpiry {
    const val DEFAULT_DAYS = 14
    const val MAX_DAYS = 90
    const val MIN_DAYS = 1

    fun clampDays(days: Int): Int = days.coerceIn(MIN_DAYS, MAX_DAYS)

    /** 90 days is trimmed by a minute so the insert stays inside the server check (published_at is set server-side, a moment later). */
    fun endsAt(days: Int, now: Instant = Instant.now()): Instant {
        val d = clampDays(days)
        val end = now.plus(java.time.Duration.ofDays(d.toLong()))
        return if (d == MAX_DAYS) end.minusSeconds(60) else end
    }
}

@Serializable
data class NoticeDismissalInsert(
    @SerialName("user_id") val userId: String,
    @SerialName("notice_id") val noticeId: String,
)

/**
 * iOS `BusinessSubscriptionPlan` ids/titles/limits/inclusions, stored as `business_profiles.selected_plan_id`
 * through `save_my_business_profile(p_selected_plan_id)`. Android shows no prices: member access is switched on
 * separately (Play Billing is not set up yet).
 */
enum class MemberPlan(val id: String, val title: String, val audience: String, val listingLimit: Int, val inclusions: List<String>) {
    LocalBusiness("local_business", "Local Member", "New local publishers", 1, listOf(
        "Verified member page", "1 active listing or poll at a time", "Basic insights: views, taps, saves and shares",
        "Verified member badge", "Edit or remove your own listings and polls",
    )),
    Growth("growth", "Growth Member", "Regular local publishers", 4, listOf(
        "Everything in Local Member", "Up to 4 active listings or polls", "Richer engagement analytics",
        "Member page with optional contact details", "Better audience insight reporting",
    )),
    Sponsor("sponsor", "Community Partner", "High-activity community publishers", 8, listOf(
        "Up to 8 active listings or polls", "Community Partner badge", "Priority member placement", "Best available insights package",
    ));

    companion object {
        fun from(id: String?) = entries.firstOrNull { it.id == id } ?: LocalBusiness
    }
}

/** iOS `PublicMemberProfileDraft` → `save_member_public_profile_with_images`. */
data class PublicPageDraft(
    val displayName: String = "",
    val areaScopeId: String = "",
    val bio: String = "",
    val contactName: String = "",
    val contactEmail: String = "",
    val phone: String = "",
    val locationText: String = "",
    val address: String = "",
    val website: String = "",
    val avatarImagePath: String? = null,
    val heroImagePath: String? = null,
    val positions: List<Double> = listOf(50.0, 50.0, 50.0, 50.0), // avatar x,y, hero x,y
) {
    /** iOS `validateHomepageDetails`: public name + area required; optional email must be usable. */
    val problems: List<String>
        get() = buildList {
            if (displayName.isBlank()) add("memberName")
            if (contactEmail.isNotBlank() && !ContactEmailValidator.isUsable(contactEmail)) add("contactEmail")
            if (areaScopeId.isBlank()) add("areaScope")
        }

    companion object {
        fun from(p: PublicMemberProfileRecord) = PublicPageDraft(
            displayName = p.displayName, areaScopeId = p.areaScopeId.orEmpty(), bio = p.bio.orEmpty(),
            contactName = p.publicContactName.orEmpty(), contactEmail = p.publicContactEmail.orEmpty(), phone = p.publicPhone.orEmpty(),
            locationText = p.publicLocationText.orEmpty(), address = p.publicAddress.orEmpty(), website = p.publicWebsite.orEmpty(),
            avatarImagePath = p.avatarImagePath, heroImagePath = p.heroImagePath,
            positions = listOf(p.avatarImagePositionX, p.avatarImagePositionY, p.heroImagePositionX, p.heroImagePositionY),
        )

        /** iOS prefill from the application when the public draft is empty. */
        fun prefill(base: PublicPageDraft, org: OrganisationDraft) = base.copy(
            displayName = base.displayName.ifBlank { org.name },
            areaScopeId = base.areaScopeId.ifBlank { org.areaScopeId },
            contactName = base.contactName.ifBlank { org.contactName },
            phone = base.phone.ifBlank { org.phone },
            address = base.address.ifBlank { org.address },
            website = base.website.ifBlank { org.website },
            bio = base.bio.ifBlank { org.about },
        )
    }
}

/** iOS `uploadMemberProfileImage`: `member-images/<user id>/<hero|avatar>-<uuid>.jpg` (bucket limit 5 MB, jpeg/png/webp). */
object MemberImagePath {
    const val BUCKET = "member-images"
    const val MAX_BYTES = 5 * 1024 * 1024
    fun make(userId: String, kind: String, imageId: String = java.util.UUID.randomUUID().toString()): String {
        val safe = if (kind == "avatar") "avatar" else "hero"
        return "${userId.lowercase()}/$safe-${imageId.lowercase()}.jpg"
    }
}
