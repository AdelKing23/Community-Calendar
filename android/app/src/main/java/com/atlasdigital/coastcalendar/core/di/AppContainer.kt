package com.atlasdigital.coastcalendar.core.di

import com.atlasdigital.coastcalendar.billing.BillingGateway
import com.atlasdigital.coastcalendar.billing.NotIntegratedBillingGateway
import com.atlasdigital.coastcalendar.core.config.SupabaseConfig
import com.atlasdigital.coastcalendar.data.remote.SupabaseProvider
import com.atlasdigital.coastcalendar.data.repository.AccountRepository
import com.atlasdigital.coastcalendar.data.repository.AuthRepository
import com.atlasdigital.coastcalendar.data.repository.EventCache
import com.atlasdigital.coastcalendar.data.repository.EventsRepository
import com.atlasdigital.coastcalendar.data.repository.ImageRepository
import com.atlasdigital.coastcalendar.data.repository.InteractionRepository
import com.atlasdigital.coastcalendar.data.repository.MemberRepository
import com.atlasdigital.coastcalendar.data.repository.OwnerListingsRepository
import com.atlasdigital.coastcalendar.data.repository.SupportAdminRepository
import com.atlasdigital.coastcalendar.data.repository.SupportRequestRepository
import com.atlasdigital.coastcalendar.data.repository.ListingRepository
import com.atlasdigital.coastcalendar.data.repository.LocationRepository
import com.atlasdigital.coastcalendar.data.repository.WelcomeRepository
import io.github.jan.supabase.SupabaseClient

/** Simple manual DI (small app; no Hilt yet). Created once in [com.atlasdigital.coastcalendar.CoastCalendarApp]. */
class AppContainer(context: android.content.Context) {
    val appContext: android.content.Context = context.applicationContext
    val prefs = com.atlasdigital.coastcalendar.core.prefs.AppPreferences(context.applicationContext)

    val isConfigured: Boolean = SupabaseConfig.isConfigured

    private val client: SupabaseClient by lazy { SupabaseProvider.create() }

    val auth by lazy { AuthRepository(client) }
    val images by lazy { ImageRepository(client) }
    val events by lazy { EventsRepository(client, images) }
    val interactions by lazy { InteractionRepository(client) }
    val members by lazy { MemberRepository(client) }
    val supportAdmin by lazy { SupportAdminRepository(client, images) }
    val supportRequests by lazy { SupportRequestRepository(client) }
    val ownerListings by lazy { OwnerListingsRepository(client, images) }
    val eventCache = EventCache()
    val locations by lazy { LocationRepository(client) }
    val account by lazy { AccountRepository(client) }
    val welcome by lazy { WelcomeRepository(client) }
    val listings by lazy { ListingRepository(client) }
    val reminders by lazy { com.atlasdigital.coastcalendar.core.reminders.EventReminderStore(appContext) }
    val billing: BillingGateway = NotIntegratedBillingGateway
}
