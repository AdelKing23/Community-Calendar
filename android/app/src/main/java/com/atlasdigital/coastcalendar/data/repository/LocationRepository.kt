package com.atlasdigital.coastcalendar.data.repository

import com.atlasdigital.coastcalendar.data.model.LocationCatalog
import com.atlasdigital.coastcalendar.data.model.LocationScope
import com.atlasdigital.coastcalendar.data.model.LocationScopeEdgeRecord
import com.atlasdigital.coastcalendar.data.model.LocationScopeKind
import com.atlasdigital.coastcalendar.data.model.LocationScopeRecord
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order

/** iOS `fetchLocationCatalog`: public + selectable `location_scopes` and `widens_to` `location_scope_edges`. */
class LocationRepository(private val client: SupabaseClient) {
    @Volatile private var cached: LocationCatalog? = null

    suspend fun catalog(): LocationCatalog {
        cached?.let { return it }
        val loaded = runCatching { fetch() }.getOrNull()
        return (loaded ?: LocationCatalog.Local).also { if (loaded != null) cached = it }
    }

    private suspend fun fetch(): LocationCatalog {
        val scopes = client.from("location_scopes").select(Columns.list("slug", "name", "scope_type", "subtitle", "sort_priority")) {
            filter {
                eq("is_public", true)
                eq("is_selectable", true)
            }
            order("sort_priority", Order.ASCENDING)
            order("name", Order.ASCENDING)
        }.decodeList<LocationScopeRecord>()
        val edges = client.from("location_scope_edges").select(Columns.list("child_slug", "parent_slug", "relationship_type", "sort_order")) {
            filter { eq("relationship_type", "widens_to") }
            order("sort_order", Order.ASCENDING)
        }.decodeList<LocationScopeEdgeRecord>()

        val remote = scopes.mapNotNull { r ->
            LocationScopeKind.fromDatabase(r.scopeType)?.let { LocationScope(r.slug, r.name, it, r.subtitle ?: r.name) }
        }
        check(remote.isNotEmpty()) { "Empty location catalogue" }
        val links = edges.groupBy { it.childSlug }.mapValues { (_, e) -> e.sortedBy { it.sortOrder }.map { it.parentSlug } }
        return LocationCatalog(remote, links.ifEmpty { LocationCatalog.Local.linksByChildId })
    }
}
