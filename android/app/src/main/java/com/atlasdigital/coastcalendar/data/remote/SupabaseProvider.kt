package com.atlasdigital.coastcalendar.data.remote

import com.atlasdigital.coastcalendar.core.config.SupabaseConfig
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.functions.Functions
import io.github.jan.supabase.postgrest.Postgrest
import io.github.jan.supabase.serializer.KotlinXSerializer
import io.github.jan.supabase.storage.Storage
import kotlinx.serialization.json.Json

/**
 * One SupabaseClient for the app. supabase-kt makes the same HTTP calls iOS and web make by hand
 * (`/auth/v1`, `/rest/v1`, `/rest/v1/rpc/{fn}`, `/functions/v1`) with the same `apikey` + Bearer headers,
 * so table, RPC and RLS contracts are identical. Storage covers `/storage/v1` (listing photos). Realtime is not installed.
 */
object SupabaseProvider {
    val json: Json = Json {
        ignoreUnknownKeys = true
        // iOS encodes optional fields with encodeIfPresent: leave nulls out of request bodies.
        explicitNulls = false
        encodeDefaults = true
        coerceInputValues = true
    }

    fun create(
        url: String = SupabaseConfig.projectUrl,
        key: String = SupabaseConfig.publishableKey,
    ): SupabaseClient = createSupabaseClient(supabaseUrl = url, supabaseKey = key) {
        defaultSerializer = KotlinXSerializer(json)
        install(Auth) {
            // Email + password only, like iOS and web (no OTP, magic link or social sign-in).
            alwaysAutoRefresh = true
            autoLoadFromStorage = true
        }
        install(Postgrest)
        install(Functions)
        // Listing photos: private `listing-images` bucket, read through signed URLs like iOS.
        install(Storage)
    }
}
