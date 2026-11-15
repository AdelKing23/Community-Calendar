package com.atlasdigital.coastcalendar.data.repository

import com.atlasdigital.coastcalendar.core.time.NzTime
import com.atlasdigital.coastcalendar.data.model.EventCategory
import com.atlasdigital.coastcalendar.data.model.EventTopicRow
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.data.model.PublicEventRecord
import com.atlasdigital.coastcalendar.data.model.PublishedEventLocationTargetRow
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order

/**
 * Public board reads, mirroring iOS `SupabaseEventService.fetchPublishedEvents(locationScopeID:)`:
 * 1. `published_event_location_targets` where location_slug = selected slug (exact-area filtering), ordered by sort_order
 * 2. `public_events` where id in (...) and end_at >= start of today, ordered is_paid_push desc, is_featured desc, start_at asc
 * 3. `event_topics` for those ids.
 * Fallback (as iOS): unscoped `public_events` if the scoped read fails.
 */
class EventsRepository(private val client: SupabaseClient) {

    suspend fun publishedEventIds(locationSlug: String): List<String> =
        client.from("published_event_location_targets").select(Columns.list("event_id", "sort_order")) {
            filter { eq("location_slug", locationSlug) }
            order("sort_order", Order.ASCENDING)
        }.decodeList<PublishedEventLocationTargetRow>().map { it.eventId }.distinct()

    suspend fun publishedEvents(locationSlug: String): List<LocalEvent> {
        val ids = publishedEventIds(locationSlug)
        if (ids.isEmpty()) return emptyList()
        val cutoff = NzTime.iso(NzTime.archiveCutoff())
        val rows = ids.chunked(150).flatMap { batch ->
            client.from("public_events").select(Columns.raw(PublicEventRecord.SELECT)) {
                filter {
                    isIn("id", batch)
                    gte("end_at", cutoff)
                }
                order("is_paid_push", Order.DESCENDING)
                order("is_featured", Order.DESCENDING)
                order("start_at", Order.ASCENDING)
            }.decodeList<PublicEventRecord>()
        }
        return withTopics(rows)
    }

    suspend fun allPublishedEvents(): List<LocalEvent> {
        val cutoff = NzTime.iso(NzTime.archiveCutoff())
        val rows = client.from("public_events").select(Columns.raw(PublicEventRecord.SELECT)) {
            filter { gte("end_at", cutoff) }
            order("is_paid_push", Order.DESCENDING)
            order("is_featured", Order.DESCENDING)
            order("start_at", Order.ASCENDING)
        }.decodeList<PublicEventRecord>()
        return withTopics(rows)
    }

    /** Scoped first, unscoped fallback (iOS Home/What's On `loadEvents`). Returns events + whether the scoped read worked. */
    suspend fun boardEvents(locationSlug: String): Pair<List<LocalEvent>, Boolean> =
        try {
            publishedEvents(locationSlug).filter { it.isPubliclyVisible } to true
        } catch (scopedError: Exception) {
            allPublishedEvents().filter { it.isPubliclyVisible } to false
        }

    private suspend fun withTopics(rows: List<PublicEventRecord>): List<LocalEvent> {
        if (rows.isEmpty()) return emptyList()
        val topics: Map<String, List<EventCategory>> = runCatching {
            client.from("event_topics").select(Columns.list("event_id", "topic_slug")) {
                filter { isIn("event_id", rows.map { it.id }) }
            }.decodeList<EventTopicRow>()
                .groupBy({ it.eventId }, { EventCategory.from(it.topicSlug) })
                .mapValues { (_, v) -> v.filterNotNull() }
        }.getOrDefault(emptyMap())
        return rows.mapNotNull { it.toLocalEvent(topics[it.id].orEmpty()) }
    }
}
