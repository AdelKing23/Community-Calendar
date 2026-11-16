package com.atlasdigital.coastcalendar.data.repository

import com.atlasdigital.coastcalendar.data.model.EventTopicInsert
import com.atlasdigital.coastcalendar.data.model.InsertedId
import com.atlasdigital.coastcalendar.data.model.ListingDraft
import com.atlasdigital.coastcalendar.data.model.MemberNoticeInsert
import com.atlasdigital.coastcalendar.data.model.PendingEventInsert
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns

/**
 * Create, mirroring iOS `submitPendingListing` + `insertEventTopics` + `createMemberNotice`.
 * Listings and polls go in as `pending_review` for Support. The server enforces subscription + allowance
 * (and exempts Support, t231); this client only mirrors the iOS gate before showing the form.
 */
class ListingRepository(private val client: SupabaseClient) {

    suspend fun submitPendingListing(draft: ListingDraft, businessProfileId: String): String {
        val body = PendingEventInsert.from(draft, businessProfileId)
        val inserted = client.from("events").insert(body) {
            select(Columns.list("id"))
        }.decodeSingle<InsertedId>()
        insertTopics(inserted.id, draft)
        return inserted.id
    }

    /** Best effort, like iOS: a topic failure does not fail the listing. */
    private suspend fun insertTopics(eventId: String, draft: ListingDraft) {
        runCatching {
            client.from("event_topics").insert(listOf(EventTopicInsert(eventId, draft.category.raw)))
        }
    }

    suspend fun createNotice(profileId: String, ownerUserId: String, title: String, summary: String, body: String, days: Int = com.atlasdigital.coastcalendar.data.model.NoticeExpiry.DEFAULT_DAYS): String =
        client.from("member_notices").insert(
            MemberNoticeInsert(
                businessProfileId = profileId,
                ownerUserId = ownerUserId,
                title = title.trim(),
                summary = summary.trim().ifEmpty { null },
                body = body.trim().ifEmpty { null },
                endsAt = com.atlasdigital.coastcalendar.core.time.NzTime.iso(com.atlasdigital.coastcalendar.data.model.NoticeExpiry.endsAt(days)),
            ),
        ) { select(Columns.list("id")) }.decodeSingle<InsertedId>().id
}
