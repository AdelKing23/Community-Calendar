package com.atlasdigital.coastcalendar.data.repository

import com.atlasdigital.coastcalendar.core.time.NzTime
import com.atlasdigital.coastcalendar.data.model.ActivePromotionRecord
import com.atlasdigital.coastcalendar.data.model.EventCategory
import com.atlasdigital.coastcalendar.data.model.EventTopicRow
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.data.model.PublicEventRecord
import com.atlasdigital.coastcalendar.data.model.PublishedEventLocationTargetRow
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

/**
 * Public board reads, mirroring iOS `SupabaseEventService.fetchPublishedEvents(locationScopeID:)`:
 * 1. `published_event_location_targets` where location_slug = selected slug (exact-area filtering), ordered by sort_order
 * 2. `public_events` where id in (...) and end_at >= start of today, ordered is_paid_push desc, is_featured desc, start_at asc
 * 3. `event_topics` for those ids.
 * 4. `public_event_images` (signed URLs) and `active_event_promotions`, both best effort.
 * Fallback (as iOS): unscoped `public_events` if the scoped read fails.
 */
class EventsRepository(private val client: SupabaseClient, private val images: ImageRepository) {

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
    /** iOS `fetchPublishedEvents(businessProfileID:)`: start_at >= now - 2 days, start_at asc. */
    suspend fun profileEvents(profileId: String): List<LocalEvent> {
        val cutoff = NzTime.iso(java.time.Instant.now().minus(java.time.Duration.ofDays(2)))
        val rows = client.from("public_events").select(Columns.raw(PublicEventRecord.SELECT)) {
            filter {
                eq("business_profile_id", profileId.lowercase())
                gte("start_at", cutoff)
            }
            order("start_at", Order.ASCENDING)
        }.decodeList<PublicEventRecord>()
        return withTopics(rows)
    }

    /** Public listings by id (iOS `fetchEventsByIDs`; Android reads `public_events`, so only published listings come back). */
    suspend fun byIds(ids: Collection<String>): List<LocalEvent> {
        val unique = ids.map { it.lowercase() }.distinct()
        if (unique.isEmpty()) return emptyList()
        val rows = unique.chunked(150).flatMap { batch ->
            client.from("public_events").select(Columns.raw(PublicEventRecord.SELECT)) {
                filter { isIn("id", batch) }
                order("start_at", Order.ASCENDING)
            }.decodeList<PublicEventRecord>()
        }
        return withTopics(rows)
    }

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
        val events = rows.mapNotNull { it.toLocalEvent(topics[it.id].orEmpty()) }
        return applyingActivePromotions(withImages(events))
    }

    /**
     * iOS `fetchHomeCalendarEvents(eventIDs:from:to:)`: public listings overlapping [rangeStart, rangeEnd)
     * (end_at >= start, start_at < end, order start_at asc). Null ids = unscoped fallback.
     */
    suspend fun homeCalendarEvents(eventIds: List<String>?, rangeStart: java.time.Instant, rangeEnd: java.time.Instant): List<LocalEvent> {
        if (eventIds != null && eventIds.isEmpty()) return emptyList()
        val from = NzTime.iso(rangeStart)
        val to = NzTime.iso(rangeEnd)
        val batches: List<List<String>?> = eventIds?.chunked(150) ?: listOf(null)
        val rows = batches.flatMap { batch ->
            client.from("public_events").select(Columns.raw(PublicEventRecord.SELECT)) {
                filter {
                    if (batch != null) isIn("id", batch)
                    gte("end_at", from)
                    lt("start_at", to)
                }
                order("start_at", Order.ASCENDING)
            }.decodeList<PublicEventRecord>()
        }
        return withTopics(rows)
    }

    /** iOS: public images are best effort ("[Home] public images skipped"). */
    suspend fun withImages(events: List<LocalEvent>): List<LocalEvent> {
        val records = runCatching { images.imageRecords(events.map { it.id }) }.getOrDefault(emptyMap())
        if (records.isEmpty()) return events
        return coroutineScope {
            events.map { event ->
                async {
                    val rows = records[event.id].orEmpty()
                    if (rows.isEmpty()) event else event.copy(images = images.signed(rows))
                }
            }.awaitAll()
        }
    }

    /**
     * iOS `applyingActivePromotions`: `active_event_promotions` (event_id in …, order placement_rank desc, paid_at asc),
     * best row per event, then `applyingActivePromotion(rank:paidAt:)`. Failure leaves events unchanged.
     */
    suspend fun applyingActivePromotions(events: List<LocalEvent>): List<LocalEvent> {
        if (events.isEmpty()) return events
        val best = runCatching { activePromotions(events.map { it.id }) }.getOrNull().orEmpty()
        if (best.isEmpty()) return events
        return events.map { event ->
            best[event.id]?.let { event.applyingActivePromotion(it.placementRank, NzTime.parse(it.paidAt)) } ?: event
        }
    }

    suspend fun activePromotions(eventIds: List<String>): Map<String, ActivePromotionRecord> {
        val rows = eventIds.map { it.lowercase() }.distinct().chunked(150).flatMap { batch ->
            client.from("active_event_promotions")
                .select(Columns.list("event_id", "tier", "placement", "starts_at", "ends_at", "paid_at", "placement_rank")) {
                    filter { isIn("event_id", batch) }
                    order("placement_rank", Order.DESCENDING)
                    order("paid_at", Order.ASCENDING)
                }.decodeList<ActivePromotionRecord>()
        }
        return bestPromotionPerEvent(rows)
    }

    companion object {
        fun bestPromotionPerEvent(rows: List<ActivePromotionRecord>): Map<String, ActivePromotionRecord> {
            val out = LinkedHashMap<String, ActivePromotionRecord>()
            for (row in rows) {
                val existing = out[row.eventId]
                if (existing == null || row.sortsBefore(existing)) out[row.eventId] = row
            }
            return out
        }
    }
}
