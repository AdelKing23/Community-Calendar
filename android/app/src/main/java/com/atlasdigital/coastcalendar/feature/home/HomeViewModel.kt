package com.atlasdigital.coastcalendar.feature.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.data.model.CoastTown
import com.atlasdigital.coastcalendar.data.model.EventFeedOrdering
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.data.model.LocationCatalog
import com.atlasdigital.coastcalendar.data.model.LocationScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class BoardState(
    val catalog: LocationCatalog = LocationCatalog.Local,
    val selectedId: String = LocationScope.DEFAULT_ID,
    val events: List<LocalEvent> = emptyList(),
    val isUsingBackendLocationFilter: Boolean = false,
    val isLoading: Boolean = true,
    val error: String? = null,
) {
    val selectedScope: LocationScope get() = catalog.defaultScope(selectedId)

    /** iOS fallback when the scoped read failed: match by local town only (iOS `LocationScope.matches`). */
    fun matchesSelectedArea(event: LocalEvent): Boolean {
        if (isUsingBackendLocationFilter) return true
        val town = CoastTown.forScopeSlug(selectedScope.id)
        return town == CoastTown.All || event.town == town
    }
}

/** Shared loader for Home and What's On (same reads and fallback as iOS `loadEvents`). */
abstract class BoardViewModel(protected val container: AppContainer, initialScopeId: String) : ViewModel() {
    protected val _state = MutableStateFlow(BoardState(selectedId = initialScopeId))
    val state: StateFlow<BoardState> = _state.asStateFlow()

    init { reload() }

    protected abstract fun persistScope(id: String)

    fun selectScope(scope: LocationScope) {
        persistScope(scope.id)
        _state.update { it.copy(selectedId = scope.id) }
        reload()
    }

    fun reload() {
        if (!container.isConfigured) {
            _state.update { it.copy(isLoading = false, error = "This build has no Supabase configuration.") }
            return
        }
        _state.update { it.copy(isLoading = it.events.isEmpty(), error = null) }
        viewModelScope.launch {
            val catalog = container.locations.catalog()
            val slug = catalog.defaultScope(_state.value.selectedId).id
            try {
                val (events, scoped) = container.events.boardEvents(slug)
                container.eventCache.put(events)
                _state.update { it.copy(catalog = catalog, events = events, isUsingBackendLocationFilter = scoped, isLoading = false) }
            } catch (e: Exception) {
                _state.update { it.copy(catalog = catalog, isLoading = false, error = "Please try again soon.") }
            }
        }
    }
}

class HomeViewModel(container: AppContainer) : BoardViewModel(container, container.prefs.homeScopeId) {
    override fun persistScope(id: String) { container.prefs.homeScopeId = id }

    /** iOS `boardEvents`: area filter then `EventFeedOrdering.board`. */
    fun boardEvents(state: BoardState): List<LocalEvent> =
        state.events.filter(state::matchesSelectedArea).sortedWith(EventFeedOrdering.board)
}
