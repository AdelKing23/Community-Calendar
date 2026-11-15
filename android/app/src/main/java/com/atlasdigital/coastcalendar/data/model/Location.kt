package com.atlasdigital.coastcalendar.data.model

enum class LocationScopeKind(val label: String, val sortOrder: Int) {
    Place("Place", 0), Community("Community", 1), WiderArea("Wider Area", 2), Region("Region", 3), Country("Country", 4);

    companion object {
        fun fromDatabase(value: String): LocationScopeKind? = when (value) {
            "place" -> Place
            "community" -> Community
            "wider_area" -> WiderArea
            "region" -> Region
            "country" -> Country
            else -> null
        }
    }
}

data class LocationScope(val id: String, val name: String, val kind: LocationScopeKind, val subtitle: String) {
    companion object {
        /** Same internal default as iOS (`LocationScope.defaultID`) and web. */
        const val DEFAULT_ID = "pohutukawa-coast"
    }
}

/**
 * iOS `LocationCatalog`: scopes from `location_scopes` (public + selectable) and `widens_to` edges.
 * Home and What's On filter by the exact selected slug through `published_event_location_targets`, as iOS does.
 */
data class LocationCatalog(
    val scopes: List<LocationScope>,
    val linksByChildId: Map<String, List<String>>,
) {
    fun scope(id: String): LocationScope? = scopes.firstOrNull { it.id == id }

    fun defaultScope(storedId: String): LocationScope =
        scope(storedId) ?: scope(LocationScope.DEFAULT_ID) ?: scopes.first()

    fun ladder(scopeId: String): List<LocationScope> {
        val out = mutableListOf<LocationScope>()
        val seen = mutableSetOf<String>()
        var current: String? = scopeId
        while (current != null && current !in seen) {
            val s = scope(current) ?: break
            out += s
            seen += current
            current = linksByChildId[current]?.firstOrNull()
        }
        return out
    }

    fun childScopes(parentId: String): List<LocationScope> =
        linksByChildId.filterValues { parentId in it }.keys.mapNotNull(::scope)
            .sortedWith(compareBy<LocationScope> { it.kind.sortOrder }.thenBy(String.CASE_INSENSITIVE_ORDER) { it.name })

    /** Parent chain only, nearest first, current and country excluded, cap 4 (iOS `ancestorScopes`). */
    fun ancestorScopes(selectedId: String, limit: Int = 4): List<LocationScope> =
        ladder(selectedId).drop(1).filter { it.kind != LocationScopeKind.Country && it.id != "new-zealand" }.take(limit)

    /** Same-parent places for a place, or children for a wider scope, cap 6 (iOS `primaryChips`). */
    fun primaryChips(selectedId: String, limit: Int = 6): List<LocationScope> {
        val selected = defaultScope(selectedId)
        if (selected.kind != LocationScopeKind.Place) return childScopes(selected.id).take(limit)
        val parent = linksByChildId[selected.id]?.firstOrNull() ?: return emptyList()
        val ancestorNames = ladder(selected.id).drop(1).map { it.name.lowercase() }.toSet()
        return childScopes(parent)
            .filter { it.id != selected.id && it.name.lowercase() !in ancestorNames }
            .take(limit)
    }

    fun search(query: String, limit: Int = 12): List<LocationScope> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return emptyList()
        val matches = scopes.filter { it.name.lowercase().contains(q) || it.id.contains(q) || it.subtitle.lowercase().contains(q) }
        val (prefix, other) = matches.partition { it.name.lowercase().startsWith(q) || it.id.startsWith(q) }
        return (prefix + other).take(limit)
    }

    /** Places a listing can be created in (iOS `listingInputScopes`). */
    val listingInputScopes: List<LocationScope> get() = scopes.filter { it.kind == LocationScopeKind.Place }

    companion object {
        /** Offline fallback used only if `location_scopes` cannot be loaded (iOS `LocationCatalog.local`, trimmed). */
        val Local: LocationCatalog by lazy {
            val towns = listOf(
                "omana" to "Omana", "beachlands" to "Beachlands", "maraetai" to "Maraetai", "whitford" to "Whitford",
                "clevedon" to "Clevedon", "kawakawa-bay" to "Kawakawa Bay", "orere-point" to "Orere Point",
                "hunua" to "Hunua", "ardmore" to "Ardmore",
            )
            val scopes = towns.map { (id, name) -> LocationScope(id, name, LocationScopeKind.Place, name) } + listOf(
                LocationScope(LocationScope.DEFAULT_ID, "Pōhutukawa Coast", LocationScopeKind.Community, "Pōhutukawa Coast"),
                LocationScope("auckland", "Auckland", LocationScopeKind.Region, "Auckland"),
                LocationScope("new-zealand", "New Zealand", LocationScopeKind.Country, "New Zealand"),
            )
            val links = towns.associate { (id, _) -> id to listOf(LocationScope.DEFAULT_ID) } +
                mapOf(LocationScope.DEFAULT_ID to listOf("auckland"), "auckland" to listOf("new-zealand"))
            LocationCatalog(scopes, links)
        }
    }
}
