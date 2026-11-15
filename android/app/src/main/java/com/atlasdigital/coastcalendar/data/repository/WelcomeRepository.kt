package com.atlasdigital.coastcalendar.data.repository

import com.atlasdigital.coastcalendar.data.model.WelcomeDismissalRow
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns

/** Server flag `public.user_welcome_dismissals` (once per account, all devices), as iOS `WelcomeDismissalService`. */
class WelcomeRepository(private val client: SupabaseClient) {
    /** true = dismissed; throws on network/server errors (callers fail open, like iOS). */
    suspend fun hasDismissed(userId: String, version: Int): Boolean =
        client.from("user_welcome_dismissals").select(Columns.list("welcome_version")) {
            filter {
                eq("user_id", userId)
                eq("welcome_version", version)
            }
        }.decodeList<WelcomeDismissalRow>().isNotEmpty()

    /** POST with Prefer: resolution=ignore-duplicates (same as iOS). */
    suspend fun recordDismissed(userId: String, version: Int) {
        client.from("user_welcome_dismissals").upsert(WelcomeDismissalRow(userId, version)) {
            ignoreDuplicates = true
        }
    }
}
