package com.atlasdigital.coastcalendar.billing

/**
 * PLACEHOLDER — Google Play Billing is NOT integrated (t237).
 *
 * Google Play requires Play Billing for the Organisation plans on Android. When Isaac says "ready":
 *  - create the three subscription products in Play Console (same plan ids/prices as iOS; confirm with Isaac first),
 *  - add `com.android.billingclient:billing-ktx` and implement [BillingGateway] with BillingClient,
 *  - add a `verify-google-play-subscription` edge function and `provider = 'google'` in `business_subscriptions`.
 * Until then the app shows no purchase UI and no payment wording, and never links to web checkout.
 */
interface BillingGateway {
    val isAvailable: Boolean
    suspend fun availablePlans(): List<PlanOffer>
}

data class PlanOffer(val planId: String, val title: String)

/** Current implementation: nothing to buy on Android yet. */
object NotIntegratedBillingGateway : BillingGateway {
    override val isAvailable: Boolean = false
    override suspend fun availablePlans(): List<PlanOffer> = emptyList()
}
