package com.atlasdigital.coastcalendar.core.prefs

import android.content.Context
import com.atlasdigital.coastcalendar.data.model.LocationScope

/**
 * Device preferences (iOS @AppStorage keys kept as names for parity).
 * Home's area choice also sets What's On, as iOS `selectLocationScope` does.
 */
class AppPreferences(context: Context) {
    private val prefs = context.getSharedPreferences("coast_calendar_prefs", Context.MODE_PRIVATE)

    var homeScopeId: String
        get() = prefs.getString(HOME_SCOPE, LocationScope.DEFAULT_ID) ?: LocationScope.DEFAULT_ID
        set(value) = prefs.edit().putString(HOME_SCOPE, value).putString(WHATS_ON_SCOPE, value).apply()

    var whatsOnScopeId: String
        get() = prefs.getString(WHATS_ON_SCOPE, LocationScope.DEFAULT_ID) ?: LocationScope.DEFAULT_ID
        set(value) = prefs.edit().putString(WHATS_ON_SCOPE, value).apply()

    /** Signed-out welcome flag on this device. */
    var signedOutWelcomeDismissed: Boolean
        get() = prefs.getBoolean(WELCOME_SIGNED_OUT, false)
        set(value) = prefs.edit().putBoolean(WELCOME_SIGNED_OUT, value).apply()

    /** Account ids (lowercased, comma-separated) that dismissed the welcome on this device (iOS t224). */
    var welcomeDismissedAccounts: String
        get() = prefs.getString(WELCOME_ACCOUNTS, "") ?: ""
        set(value) = prefs.edit().putString(WELCOME_ACCOUNTS, value).apply()

    /** iOS `EventEngagementStore` sets (device only, not synced). */
    fun engagementIds(kind: Engagement): Set<String> = prefs.getStringSet(kind.key, emptySet()).orEmpty().toSet()

    fun toggleEngagement(kind: Engagement, eventId: String): Boolean {
        val set = engagementIds(kind).toMutableSet()
        val now = if (!set.remove(eventId.uppercase())) { set.add(eventId.uppercase()); true } else false
        prefs.edit().putStringSet(kind.key, set).apply()
        return now
    }

    fun hasEngagement(kind: Engagement, eventId: String): Boolean = eventId.uppercase() in engagementIds(kind)

    enum class Engagement(val key: String) {
        Interested("community_calendar_interested_events"),
        Going("community_calendar_going_events"),
        Saved("community_calendar_saved_events"),
    }

    private companion object {
        const val HOME_SCOPE = "communityCalendar.home.locationScope"
        const val WHATS_ON_SCOPE = "communityCalendar.whatsOn.locationScope"
        const val WELCOME_SIGNED_OUT = "communityCalendar.welcome.signedOutDismissed"
        const val WELCOME_ACCOUNTS = "communityCalendar.welcome.dismissedAccounts"
    }
}
