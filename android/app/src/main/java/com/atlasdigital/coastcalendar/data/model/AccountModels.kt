package com.atlasdigital.coastcalendar.data.model

import com.atlasdigital.coastcalendar.core.time.NzTime
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant

enum class BusinessProfileStatus(val raw: String) {
    PendingReview("pending_review"), Approved("approved"), Rejected("rejected"), Suspended("suspended"), Archived("archived");

    companion object {
        fun from(raw: String?): BusinessProfileStatus = entries.firstOrNull { it.raw == raw } ?: PendingReview
    }
}

/** Row from the `my_business_profile` RPC (subset of iOS `BusinessProfileRecord`). */
@Serializable
data class BusinessProfileRecord(
    val id: String,
    @SerialName("owner_user_id") val ownerUserId: String,
    @SerialName("business_name") val businessName: String,
    @SerialName("contact_name") val contactName: String? = null,
    @SerialName("contact_email") val contactEmail: String? = null,
    @SerialName("organisation_type") val organisationType: String? = null,
    val phone: String? = null,
    val address: String? = null,
    val website: String? = null,
    val about: String? = null,
    @SerialName("selected_plan_id") val selectedPlanId: String? = null,
    @SerialName("hero_image_url") val heroImageUrl: String? = null,
    @SerialName("avatar_image_url") val avatarImageUrl: String? = null,
    @SerialName("hero_image_position_x") val heroImagePositionX: Double = 50.0,
    @SerialName("hero_image_position_y") val heroImagePositionY: Double = 50.0,
    @SerialName("avatar_image_position_x") val avatarImagePositionX: Double = 50.0,
    @SerialName("avatar_image_position_y") val avatarImagePositionY: Double = 50.0,
    @SerialName("area_scope_id") val areaScopeId: String? = null,
    val status: String,
    @SerialName("rejection_reason") val rejectionReason: String? = null,
    @SerialName("suspension_reason") val suspensionReason: String? = null,
    @SerialName("support_note") val supportNote: String? = null,
) {
    val memberStatus: BusinessProfileStatus get() = BusinessProfileStatus.from(status)
    val isApproved: Boolean get() = memberStatus == BusinessProfileStatus.Approved
}

/** Row from `business_subscriptions` (subset of iOS `BusinessSubscriptionRecord`). Provider today: apple | stripe; Android will add google. */
@Serializable
data class BusinessSubscriptionRecord(
    val id: String,
    @SerialName("business_profile_id") val businessProfileId: String,
    @SerialName("plan_id") val planId: String,
    val status: String,
    @SerialName("active_listing_limit") val activeListingLimit: Int = 0,
    @SerialName("current_period_end") val currentPeriodEnd: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
) {
    private val periodEnd: Instant? get() = NzTime.parse(currentPeriodEnd)

    fun isCurrentlyActive(now: Instant = Instant.now()): Boolean {
        if (status != "active" && status != "trialing" && status != "grace_period") return false
        val end = periodEnd ?: return false
        return end >= now
    }

    fun isPaidThroughActive(now: Instant = Instant.now()): Boolean {
        if (isCurrentlyActive(now)) return true
        if (status != "cancelled") return false
        val end = periodEnd ?: return false
        return end >= now
    }
}

/**
 * iOS `BusinessAccountState` gates, unchanged:
 * Create needs an approved Organisation AND (an active subscription OR Support).
 * t231: Support is the only free path; the server never counts Support listings in an allowance.
 * Allowance itself is enforced server-side at insert (same as iOS build 11).
 */
data class BusinessAccountState(
    val profile: BusinessProfileRecord? = null,
    val subscriptions: List<BusinessSubscriptionRecord> = emptyList(),
    val isSupport: Boolean = false,
) {
    fun activeSubscription(now: Instant = Instant.now()): BusinessSubscriptionRecord? =
        subscriptions.filter { it.isPaidThroughActive(now) }
            .sortedWith(compareByDescending<BusinessSubscriptionRecord> { it.isCurrentlyActive(now) }
                .thenByDescending { NzTime.parse(it.currentPeriodEnd) ?: Instant.MAX })
            .firstOrNull()

    val isOrganisationApproved: Boolean get() = profile?.isApproved == true
    val hasActiveOrganisationSubscription: Boolean get() = activeSubscription() != null

    val canSubmitAsOrganisation: Boolean
        get() = isOrganisationApproved && (hasActiveOrganisationSubscription || isSupport)

    companion object {
        val Empty = BusinessAccountState()
    }
}
