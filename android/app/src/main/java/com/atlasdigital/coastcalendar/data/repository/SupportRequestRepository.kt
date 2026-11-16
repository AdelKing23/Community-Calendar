package com.atlasdigital.coastcalendar.data.repository

import com.atlasdigital.coastcalendar.data.model.SupportRequestRecord
import com.atlasdigital.coastcalendar.data.model.SupportTopic
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** iOS Contact Support: RPC `submit_support_request(p_topic, p_message, p_listing_reference)` + own `support_requests`. */
class SupportRequestRepository(private val client: SupabaseClient) {
    suspend fun submit(topic: SupportTopic, message: String, listingReference: String?): String =
        submitRaw(topic.raw, message, listingReference)

    /** Raw topic, e.g. iOS "Account deletion" (Support dashboard shows Complete deletion for topics containing "deletion"). */
    suspend fun submitRaw(topic: String, message: String, listingReference: String?): String =
        client.postgrest.rpc(
            "submit_support_request",
            buildJsonObject {
                put("p_topic", topic)
                put("p_message", message.trim())
                put("p_listing_reference", listingReference?.trim()?.takeIf { it.isNotEmpty() }?.let(::JsonPrimitive) ?: JsonNull)
            },
        ).decodeAs<String>()

    suspend fun mine(userId: String): List<SupportRequestRecord> =
        client.from("support_requests").select {
            filter { eq("submitted_by", userId.lowercase()) }
            order("created_at", Order.DESCENDING)
        }.decodeList<SupportRequestRecord>()
}
