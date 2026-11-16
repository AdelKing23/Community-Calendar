package com.atlasdigital.coastcalendar.feature.hosts

import androidx.lifecycle.viewModelScope
import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.data.model.HostDirectoryItem
import com.atlasdigital.coastcalendar.data.model.LocationCatalog
import com.atlasdigital.coastcalendar.data.model.PublicMemberProfileRecord
import com.atlasdigital.coastcalendar.feature.home.BoardState
import com.atlasdigital.coastcalendar.feature.home.BoardViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** iOS `HostsScreen.loadHosts`: approved public profiles + published events, filtered to the selected area. */
class HostsViewModel(container: AppContainer) : BoardViewModel(container, container.prefs.hostsScopeId) {
    override fun persistScope(id: String) { container.prefs.hostsScopeId = id }

    private val _profiles = MutableStateFlow<List<PublicMemberProfileRecord>>(emptyList())
    val profiles = _profiles.asStateFlow()

    init { loadProfiles() }

    fun loadProfiles() {
        if (!container.isConfigured) return
        viewModelScope.launch {
            runCatching { container.members.approvedProfiles() }.onSuccess { _profiles.value = it }
        }
    }

    fun refresh() { reload(); loadProfiles() }

    fun visibleHosts(state: BoardState, profiles: List<PublicMemberProfileRecord>): List<HostDirectoryItem> {
        val covered = coveredIds(state.catalog, state.selectedScope.id)
        val events = state.events.filter { state.matchesSelectedArea(it) }
        return HostDirectoryItem.build(profiles, events)
            .filter { h -> (h.profile.areaScopeId != null && h.profile.areaScopeId in covered) || h.events.isNotEmpty() }
            .sortedWith(HostDirectoryItem.recommended)
    }

    companion object {
        fun coveredIds(catalog: LocationCatalog, id: String): Set<String> {
            val out = mutableSetOf(id)
            val queue = ArrayDeque(listOf(id))
            while (queue.isNotEmpty()) {
                catalog.childScopes(queue.removeFirst()).forEach { if (out.add(it.id)) queue.add(it.id) }
            }
            return out
        }
    }
}
