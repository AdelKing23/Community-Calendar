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
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId

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
        onScopeChanged()
    }

    protected open fun onScopeChanged() {}

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

data class HomeCalendarState(
    val mode: HomeViewMode = HomeViewMode.Board,
    val months: List<YearMonth> = emptyList(),
    val eventsByMonth: Map<YearMonth, List<LocalEvent>> = emptyMap(),
    val loadingMonths: Set<YearMonth> = emptySet(),
    val failedMonths: Set<YearMonth> = emptySet(),
    val selectedDay: LocalDate? = null,
) {
    val canLoadMore: Boolean get() = months.size < HomeCalendarLogic.MAXIMUM_MONTH_COUNT
}

class HomeViewModel(container: AppContainer) : BoardViewModel(container, container.prefs.homeScopeId) {
    override fun persistScope(id: String) { container.prefs.homeScopeId = id }

    // MARK: Home calendar (iOS HomeCalendarStore)
    val zone: ZoneId = ZoneId.systemDefault()
    private val _calendar = MutableStateFlow(HomeCalendarState(mode = HomeViewMode.from(container.prefs.homeViewMode)))
    val calendar: StateFlow<HomeCalendarState> = _calendar.asStateFlow()
    private var calendarScopeId: String? = null
    private var scopedIds: List<String>? = null
    private var usesLocalScopeFilter = false

    init {
        if (_calendar.value.mode == HomeViewMode.Calendar) prepareCalendar()
    }

    fun toggleViewMode() {
        val next = if (_calendar.value.mode == HomeViewMode.Board) HomeViewMode.Calendar else HomeViewMode.Board
        container.prefs.homeViewMode = next.raw
        _calendar.update { it.copy(mode = next) }
        if (next == HomeViewMode.Calendar) prepareCalendar()
    }

    fun selectDay(day: LocalDate?) = _calendar.update { it.copy(selectedDay = day) }

    fun eventsOn(day: LocalDate): List<LocalEvent> =
        HomeCalendarLogic.dayEvents(_calendar.value.eventsByMonth[YearMonth.from(day)].orEmpty(), day, zone)

    fun prepareCalendar(force: Boolean = false) {
        if (!container.isConfigured) return
        val current = YearMonth.from(Instant.now().atZone(zone))
        viewModelScope.launch {
            // Same slug the board uses once the area catalogue is loaded (iOS waits for hasLoadedLocationCatalog).
            val scopeId = container.locations.catalog().defaultScope(_state.value.selectedId).id
            if (force || calendarScopeId != scopeId || _calendar.value.months.firstOrNull() != current) {
                calendarScopeId = scopeId
                _calendar.update {
                    it.copy(
                        months = HomeCalendarLogic.monthStarts(Instant.now(), HomeCalendarLogic.INITIAL_MONTH_COUNT, zone),
                        eventsByMonth = emptyMap(), failedMonths = emptySet(),
                    )
                }
                try {
                    scopedIds = container.events.publishedEventIds(scopeId)
                    usesLocalScopeFilter = false
                } catch (e: Exception) {
                    scopedIds = null
                    usesLocalScopeFilter = true
                }
            }
            loadMissingMonths()
        }
    }

    fun loadMoreMonths() {
        val c = _calendar.value
        val last = c.months.lastOrNull() ?: return
        if (!c.canLoadMore || c.loadingMonths.isNotEmpty()) return
        val extra = (1..HomeCalendarLogic.MONTHS_PER_LOAD).map { last.plusMonths(it.toLong()) }
            .take(HomeCalendarLogic.MAXIMUM_MONTH_COUNT - c.months.size)
        _calendar.update { it.copy(months = it.months + extra) }
        viewModelScope.launch { loadMissingMonths() }
    }

    fun retryMonth(month: YearMonth) {
        _calendar.update { it.copy(failedMonths = it.failedMonths - month) }
        viewModelScope.launch { loadMonth(month) }
    }

    private suspend fun loadMissingMonths() {
        for (month in _calendar.value.months) {
            val c = _calendar.value
            if (month !in c.eventsByMonth && month !in c.loadingMonths && month !in c.failedMonths) loadMonth(month)
        }
    }

    private suspend fun loadMonth(month: YearMonth) {
        val requestedScope = calendarScopeId
        val now = Instant.now()
        _calendar.update { it.copy(loadingMonths = it.loadingMonths + month) }
        try {
            // Start of today, so listings that ended earlier today still load (shown as Finished until midnight).
            val rangeStart = maxOf(month.atDay(1).atStartOfDay(zone).toInstant(), now.atZone(zone).toLocalDate().atStartOfDay(zone).toInstant())
            val rangeEnd = month.plusMonths(1).atDay(1).atStartOfDay(zone).toInstant()
            val events = container.events.homeCalendarEvents(scopedIds, rangeStart, rangeEnd)
            if (requestedScope != calendarScopeId) return
            val board = _state.value
            val shown = events.filter {
                HomeCalendarLogic.isShownOnHome(it, now, zone) && (!usesLocalScopeFilter || board.copy(isUsingBackendLocationFilter = false).matchesSelectedArea(it))
            }
            container.eventCache.put(shown)
            _calendar.update { it.copy(eventsByMonth = it.eventsByMonth + (month to shown)) }
        } catch (e: Exception) {
            if (requestedScope == calendarScopeId) _calendar.update { it.copy(failedMonths = it.failedMonths + month) }
        } finally {
            _calendar.update { it.copy(loadingMonths = it.loadingMonths - month) }
        }
    }

    override fun onScopeChanged() {
        if (_calendar.value.mode == HomeViewMode.Calendar) prepareCalendar()
    }

    /** iOS `boardEvents`: area filter then `EventFeedOrdering.board`. */
    fun boardEvents(state: BoardState): List<LocalEvent> =
        state.events.filter(state::matchesSelectedArea).sortedWith(EventFeedOrdering.board)
}
