package com.atlasdigital.coastcalendar.data.repository

import com.atlasdigital.coastcalendar.data.model.EventChangeRequestInsert
import com.atlasdigital.coastcalendar.data.model.EventChangeRequestRecord
import com.atlasdigital.coastcalendar.data.model.EventChangeType
import com.atlasdigital.coastcalendar.data.model.ListingEditDraft
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.data.model.PublicEventRecord
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * My Listings, mirroring iOS:
 * - `fetchUserListings`: `events?select=*,event_images(*)&submitted_by=eq.<me>&order=created_at.desc,start_at.asc`;
 * - `fetchMyChangeRequests`: `event_change_requests?select=*,events(*,event_images(*))&requested_by=eq.<me>&order=created_at.desc`;
 * - `createEditRequest`: insert a pending `edit_request` with `ListingEditDraft.proposedChanges` (the live listing does not change);
 * - Remove: RPC `owner_archive_own_listing(p_event_id)` (build 11 archives straight away; Support can restore).
 */
class OwnerListingsRepository(private val client: SupabaseClient, private val images: ImageRepository) {

    suspend fun userListings(userId: String): List<LocalEvent> {
        val rows = client.from("events").select(Columns.raw("*,event_images(*)")) {
            filter { eq("submitted_by", userId.lowercase()) }
            order("created_at", Order.DESCENDING)
            order("start_at", Order.ASCENDING)
        }.decodeList<PublicEventRecord>()
        return rows.mapNotNull { record -> record.toLocalEvent()?.withSignedImages(record) }
    }

    suspend fun myChangeRequests(userId: String): List<EventChangeRequestRecord> =
        client.from("event_change_requests").select(Columns.raw(EventChangeRequestRecord.SELECT)) {
            filter { eq("requested_by", userId.lowercase()) }
            order("created_at", Order.DESCENDING)
        }.decodeList<EventChangeRequestRecord>()

    suspend fun createEditRequest(event: LocalEvent, draft: ListingEditDraft, requesterId: String, note: String?) {
        client.from("event_change_requests").insert(
            EventChangeRequestInsert(
                eventId = event.id.lowercase(),
                requestedBy = requesterId.lowercase(),
                changeType = EventChangeType.EditRequest.raw,
                proposedChanges = draft.proposedChanges(),
                requesterNote = note?.trim()?.takeIf { it.isNotEmpty() },
            ),
        )
    }

    suspend fun archiveOwnListing(eventId: String) {
        client.postgrest.rpc("owner_archive_own_listing", buildJsonObject { put("p_event_id", eventId.lowercase()) })
    }

    suspend fun LocalEvent.withSignedImages(record: PublicEventRecord): LocalEvent {
        val rows = record.eventImages.orEmpty()
        return if (rows.isEmpty()) this else copy(images = this@OwnerListingsRepository.images.signed(rows))
    }
}
