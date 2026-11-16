package com.atlasdigital.coastcalendar.data.repository

import com.atlasdigital.coastcalendar.core.time.NzTime
import com.atlasdigital.coastcalendar.data.model.BusinessProfileRecord
import com.atlasdigital.coastcalendar.data.model.BusinessProfileStatus
import com.atlasdigital.coastcalendar.data.model.EventChangeRequestRecord
import com.atlasdigital.coastcalendar.data.model.EventChangeRequestStatus
import com.atlasdigital.coastcalendar.data.model.EventChangeType
import com.atlasdigital.coastcalendar.data.model.EventReportRecord
import com.atlasdigital.coastcalendar.data.model.EventReportStatus
import com.atlasdigital.coastcalendar.data.model.EventReviewReason
import com.atlasdigital.coastcalendar.data.model.ListingStatus
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.data.model.PublicEventRecord
import com.atlasdigital.coastcalendar.data.model.SupportRequestRecord
import com.atlasdigital.coastcalendar.data.model.SupportRequestStatus
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant

/**
 * iOS `OwnerEventReviewing` for the Support dashboard. Reads rely on the same RLS as iOS (Support accounts only);
 * writes use the same RPCs / PATCHes.
 */
class SupportAdminRepository(private val client: SupabaseClient, private val images: ImageRepository) {
    private fun String?.orNull() = this?.trim()?.takeIf { it.isNotEmpty() }?.let(::JsonPrimitive) ?: JsonNull

    suspend fun isSupport(): Boolean = client.postgrest.rpc("current_user_is_support").decodeAs<Boolean>()

    /** iOS `fetchOwnerEvents`: `events?select=*,event_images(*)&order=created_at.desc,start_at.asc`. Images signed for pending only. */
    suspend fun allEvents(): List<LocalEvent> {
        val rows = client.from("events").select(Columns.raw("*,event_images(*)")) {
            order("created_at", Order.DESCENDING)
            order("start_at", Order.ASCENDING)
        }.decodeList<PublicEventRecord>()
        return rows.mapNotNull { r ->
            val e = r.toLocalEvent() ?: return@mapNotNull null
            val imgs = r.eventImages.orEmpty()
            if (e.status == ListingStatus.PendingReview && imgs.isNotEmpty()) e.copy(images = images.signed(imgs)) else e
        }
    }

    suspend fun memberProfiles(): List<BusinessProfileRecord> =
        client.postgrest.rpc("support_member_profiles").decodeList<BusinessProfileRecord>()

    suspend fun changeRequests(): List<EventChangeRequestRecord> =
        client.from("event_change_requests").select(Columns.raw(EventChangeRequestRecord.SELECT)) {
            order("created_at", Order.DESCENDING)
        }.decodeList<EventChangeRequestRecord>()

    suspend fun supportRequests(): List<SupportRequestRecord> =
        client.from("support_requests").select { order("created_at", Order.DESCENDING) }.decodeList<SupportRequestRecord>()

    suspend fun eventReports(): List<EventReportRecord> =
        client.from("event_reports").select(Columns.raw("*,events(*,event_images(*))")) {
            order("created_at", Order.DESCENDING)
        }.decodeList<EventReportRecord>()

    suspend fun moderateListing(eventId: String, status: ListingStatus) {
        client.postgrest.rpc("support_transition_listing_moderation", buildJsonObject {
            put("p_event_id", eventId.lowercase())
            put("p_target_status", status.raw)
            put("p_reason", JsonNull)
        })
    }

    suspend fun transitionMember(profileId: String, status: BusinessProfileStatus, reason: String?, note: String?) {
        client.postgrest.rpc("support_transition_member_profile", buildJsonObject {
            put("p_business_profile_id", profileId.lowercase())
            put("p_target_status", status.raw)
            put("p_reason", reason?.trim().orEmpty())
            put("p_support_note", note?.trim().orEmpty())
        })
        if (status != BusinessProfileStatus.Approved) {
            val r = reason?.trim()?.takeIf { it.isNotEmpty() } ?: note?.trim()?.takeIf { it.isNotEmpty() } ?: "Membership moved to ${status.raw}"
            client.postgrest.rpc("support_unpublish_member_public_profile", buildJsonObject {
                put("p_business_profile_id", profileId.lowercase())
                put("p_reason", r)
            })
        }
    }

    suspend fun updateSupportRequest(id: String, status: SupportRequestStatus, note: String?) {
        client.from("support_requests").update(buildJsonObject {
            put("status", status.raw)
            put("support_note", note.orNull())
        }) { filter { eq("id", id.lowercase()) } }
    }

    suspend fun completeAccountDeletion(requestId: String, note: String?) {
        client.postgrest.rpc("support_complete_account_deletion", buildJsonObject {
            put("p_request_id", requestId.lowercase())
            put("p_support_note", note.orNull())
        })
    }

    suspend fun updateEventReport(id: String, status: EventReportStatus) {
        client.from("event_reports").update(buildJsonObject {
            put("status", status.raw)
            put("reviewed_at", NzTime.iso(Instant.now()))
        }) { filter { eq("id", id.lowercase()) } }
    }

    /** iOS `supportApproveChangeRequest`: edit → RPC apply; removal → archive listing + mark applied. */
    suspend fun approveChangeRequest(request: EventChangeRequestRecord, reason: EventReviewReason, note: String?) {
        when (request.type) {
            EventChangeType.EditRequest -> client.postgrest.rpc("support_apply_event_change_request", buildJsonObject {
                put("p_change_request_id", request.id.lowercase())
                put("p_review_reason", reason.raw)
                put("p_support_note", note.orNull())
            })
            EventChangeType.RemovalRequest -> {
                moderateListing(request.eventId, ListingStatus.Archived)
                updateChangeRequest(request.id, EventChangeRequestStatus.Applied, reason, note, applied = true)
            }
        }
    }

    suspend fun rejectChangeRequest(id: String, reason: EventReviewReason, note: String?) =
        updateChangeRequest(id, EventChangeRequestStatus.Rejected, reason, note, applied = false)

    private suspend fun updateChangeRequest(id: String, status: EventChangeRequestStatus, reason: EventReviewReason, note: String?, applied: Boolean) {
        val now = NzTime.iso(Instant.now())
        client.from("event_change_requests").update(buildJsonObject {
            put("status", status.raw)
            put("review_reason", reason.raw)
            note?.trim()?.takeIf { it.isNotEmpty() }?.let { put("support_note", it) }
            put("reviewed_at", now)
            if (applied) put("applied_at", now)
        }) { filter { eq("id", id.lowercase()) } }
    }
}
