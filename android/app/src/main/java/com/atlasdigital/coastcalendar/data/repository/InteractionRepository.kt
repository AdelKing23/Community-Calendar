package com.atlasdigital.coastcalendar.data.repository

import com.atlasdigital.coastcalendar.data.model.EventReportCategory
import com.atlasdigital.coastcalendar.data.model.PollDetails
import com.atlasdigital.coastcalendar.data.model.PollResponseCountRecord
import com.atlasdigital.coastcalendar.data.model.PollResults
import com.atlasdigital.coastcalendar.data.model.PollUserResponse
import com.atlasdigital.coastcalendar.data.model.PublicMemberProfileRecord
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Detail-screen reads/writes: polls, reports and the public organiser card. Same tables/RPCs as iOS. */
class InteractionRepository(private val client: SupabaseClient) {

    /** iOS `fetchPollResponseCounts`: RPC `poll_response_counts_for_event(p_event_id)`. */
    suspend fun pollCounts(eventId: String): PollResults = PollResults(
        client.postgrest.rpc("poll_response_counts_for_event", buildJsonObject { put("p_event_id", eventId.lowercase()) })
            .decodeList<PollResponseCountRecord>(),
    )

    /** iOS `fetchMyPollResponse`. */
    suspend fun myPollResponse(eventId: String, userId: String): PollUserResponse? =
        client.from("event_poll_responses").select(Columns.list("selected_option", "custom_answer", "updated_at")) {
            filter {
                eq("event_id", eventId.lowercase())
                eq("respondent_id", userId.lowercase())
            }
            limit(1)
        }.decodeList<PollUserResponse>().firstOrNull()

    /**
     * iOS `submitPollResponse`: upsert on (event_id, respondent_id), merge duplicates. One answer per person:
     * either an option or a custom answer (≤ 250 chars); the other is sent as explicit null, as iOS does.
     */
    suspend fun submitPollResponse(eventId: String, userId: String, selectedOption: String?, customAnswer: String?) {
        val option = selectedOption?.trim()?.takeIf { it.isNotEmpty() }
        val custom = customAnswer?.trim()?.take(PollDetails.CUSTOM_ANSWER_LIMIT)?.takeIf { it.isNotEmpty() }
        val body = buildJsonObject {
            put("event_id", eventId.lowercase())
            put("respondent_id", userId.lowercase())
            put("selected_option", option?.let(::JsonPrimitive) ?: JsonNull)
            put("custom_answer", custom?.let(::JsonPrimitive) ?: JsonNull)
        }
        client.from("event_poll_responses").upsert(body) {
            onConflict = "event_id,respondent_id"
        }
    }

    /** iOS `withdrawPollResponse`: DELETE where event_id = id (RLS limits it to the caller's row). */
    suspend fun withdrawPollResponse(eventId: String) {
        client.from("event_poll_responses").delete {
            filter { eq("event_id", eventId.lowercase()) }
        }
    }

    /** iOS `submitEventReport`: RPC `submit_event_report(p_event_id, p_category, p_details)`. Sign-in required. */
    suspend fun submitEventReport(eventId: String, category: EventReportCategory, details: String?) {
        val trimmed = details?.trim()?.takeIf { it.isNotEmpty() }
        client.postgrest.rpc(
            "submit_event_report",
            buildJsonObject {
                put("p_event_id", eventId.lowercase())
                put("p_category", category.raw)
                put("p_details", trimmed?.let(::JsonPrimitive) ?: JsonNull)
            },
        )
    }

    /** iOS `fetchBusinessProfile(profileID:)`: `public_host_directory`, published only. */
    suspend fun publicProfile(profileId: String): PublicMemberProfileRecord? =
        client.from("public_host_directory").select(Columns.raw(PublicMemberProfileRecord.SELECT)) {
            filter {
                eq("id", profileId.lowercase())
                filterNot("published_at", io.github.jan.supabase.postgrest.query.filter.FilterOperator.IS, "null")
            }
            limit(1)
        }.decodeList<PublicMemberProfileRecord>().firstOrNull()
}
