package com.atlasdigital.coastcalendar.data.repository

import com.atlasdigital.coastcalendar.data.model.BusinessAccountState
import com.atlasdigital.coastcalendar.data.model.BusinessProfileRecord
import com.atlasdigital.coastcalendar.data.model.BusinessSubscriptionRecord
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.rpc

/**
 * iOS `fetchBusinessAccount`: `my_business_profile` RPC + `business_subscriptions` for the owner,
 * plus `current_user_is_support` RPC (t231). A failed Support check means "not Support" (fails closed).
 */
class AccountRepository(private val client: SupabaseClient) {

    suspend fun businessAccount(userId: String): BusinessAccountState {
        val profiles = client.postgrest.rpc("my_business_profile").decodeList<BusinessProfileRecord>()
        val subscriptions = client.from("business_subscriptions").select {
            filter { eq("owner_user_id", userId) }
            order("created_at", Order.DESCENDING)
        }.decodeList<BusinessSubscriptionRecord>()
        return BusinessAccountState(
            profile = profiles.firstOrNull(),
            subscriptions = subscriptions,
            isSupport = isSupport(),
        )
    }

    suspend fun isSupport(): Boolean =
        runCatching { client.postgrest.rpc("current_user_is_support").decodeAs<Boolean>() }.getOrDefault(false)
}
