package com.atlasdigital.coastcalendar.data.repository

import com.atlasdigital.coastcalendar.core.time.NzTime
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.data.model.PublicEventRecord
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Duration
import java.time.Instant

/** A calendar entry plus whether it is an org-calendar note and whether it's private to people who Belong. */
data class CalendarItem(val event: LocalEvent, val isNote: Boolean, val isPrivate: Boolean)

@Serializable
private data class CalendarRow(val id: String, val visibility: String? = null)

/**
 * iOS My Calendar / Org calendar contracts:
 * - `fetch_my_calendar_listings()` org-calendar notes from organisations you Belong to (or own) + your Going listings.
 * - `fetch_org_calendar_listings(p_profile_id)` + the organisation's published listings.
 * - `owner_insert_org_calendar_listing(...)` for the owner's "Create on this day".
 */
class CalendarRepository(private val client: SupabaseClient, private val events: EventsRepository) {

    private suspend fun rpcItems(name: String, params: kotlinx.serialization.json.JsonObject): List<CalendarItem> {
        val result = client.postgrest.rpc(name, params)
        val rows = result.decodeList<PublicEventRecord>()
        val visibility = runCatching { result.decodeList<CalendarRow>() }.getOrDefault(emptyList()).associate { it.id to it.visibility }
        return rows.mapNotNull { r -> r.toLocalEvent()?.let { CalendarItem(it, isNote = true, isPrivate = visibility[r.id] == "private") } }
    }

    suspend fun myCalendar(goingIds: Collection<String>): List<CalendarItem> {
        val notes = rpcItems("fetch_my_calendar_listings", buildJsonObject { })
        val going = if (goingIds.isEmpty()) emptyList() else runCatching { events.byIds(goingIds) }.getOrDefault(emptyList())
        return merge(notes, going.map { CalendarItem(it, isNote = false, isPrivate = false) })
    }

    suspend fun orgCalendar(profileId: String): List<CalendarItem> {
        val notes = rpcItems("fetch_org_calendar_listings", buildJsonObject { put("p_profile_id", profileId.lowercase()) })
        val published = runCatching { events.profileEvents(profileId) }.getOrDefault(emptyList())
        return merge(notes, published.map { CalendarItem(it, isNote = false, isPrivate = false) })
    }

    /** iOS `insertOrgCalendarListing`: start at the chosen time on that day, 2 hours long, town "Beachlands", no scope. */
    suspend fun insertOrgCalendarListing(profileId: String, title: String, venue: String, details: String, start: Instant, isPublic: Boolean): String {
        val result = client.postgrest.rpc(
            "owner_insert_org_calendar_listing",
            buildJsonObject {
                put("p_profile_id", profileId.lowercase())
                put("p_title", title.trim())
                put("p_start_at", NzTime.iso(start))
                put("p_end_at", NzTime.iso(start.plus(Duration.ofHours(2))))
                put("p_visibility", if (isPublic) "public" else "private")
                put("p_town", "Beachlands")
                put("p_location_scope_id", "")
                put("p_location_display_name", venue.trim())
                put("p_venue", venue.trim())
                put("p_details", details.trim())
            },
        )
        return result.data.trim().trim('"')
    }

    private fun merge(a: List<CalendarItem>, b: List<CalendarItem>): List<CalendarItem> {
        val seen = HashSet<String>()
        return (a + b).filter { seen.add(it.event.id.lowercase()) }
    }
}
