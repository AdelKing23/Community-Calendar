package com.atlasdigital.coastcalendar.core.di

import com.atlasdigital.coastcalendar.billing.BillingGateway
import com.atlasdigital.coastcalendar.billing.NotIntegratedBillingGateway
import com.atlasdigital.coastcalendar.core.config.SupabaseConfig
import com.atlasdigital.coastcalendar.data.remote.SupabaseProvider
import com.atlasdigital.coastcalendar.data.repository.AccountRepository
import com.atlasdigital.coastcalendar.data.repository.AuthRepository
import com.atlasdigital.coastcalendar.data.repository.EventsRepository
import com.atlasdigital.coastcalendar.data.repository.ListingRepository
import com.atlasdigital.coastcalendar.data.repository.LocationRepository
import com.atlasdigital.coastcalendar.data.repository.WelcomeRepository
import io.github.jan.supabase.SupabaseClient

/** Simple manual DI (small app; no Hilt yet). Created once in [com.atlasdigital.coastcalendar.CoastCalendarApp]. */
class AppContainer(context: android.content.Context) {
    val prefs = com.atlasdigital.coastcalendar.core.prefs.AppPreferences(context.applicationContext)

    val isConfigured: Boolean = SupabaseConfig.isConfigured

    private val client: SupabaseClient by lazy { SupabaseProvider.create() }

    val auth by lazy { AuthRepository(client) }
    val events by lazy { EventsRepository(client) }
    val locations by lazy { LocationRepository(client) }
    val account by lazy { AccountRepository(client) }
    val welcome by lazy { WelcomeRepository(client) }
    val listings by lazy { ListingRepository(client) }
    val billing: BillingGateway = NotIntegratedBillingGateway
}
