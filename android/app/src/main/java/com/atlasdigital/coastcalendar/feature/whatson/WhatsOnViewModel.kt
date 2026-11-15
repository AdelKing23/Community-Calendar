package com.atlasdigital.coastcalendar.feature.whatson

import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.data.model.DateScope
import com.atlasdigital.coastcalendar.data.model.EventCategory
import com.atlasdigital.coastcalendar.data.model.EventFeedOrdering
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.feature.home.BoardState
import com.atlasdigital.coastcalendar.feature.home.BoardViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class WhatsOnViewModel(container: AppContainer) : BoardViewModel(container, container.prefs.whatsOnScopeId) {
    override fun persistScope(id: String) { container.prefs.whatsOnScopeId = id }

    private val _dateScope = MutableStateFlow(DateScope.Today)
    val dateScope: StateFlow<DateScope> = _dateScope.asStateFlow()
    private val _topic = MutableStateFlow<EventCategory?>(null)
    val topic: StateFlow<EventCategory?> = _topic.asStateFlow()

    fun setDateScope(scope: DateScope) { _dateScope.value = scope }
    fun setTopic(topic: EventCategory?) { _topic.value = topic }

    /** iOS `visibleEvents`: date scope, area, topic, then `EventFeedOrdering.discovery`. */
    fun visibleEvents(state: BoardState, scope: DateScope, topic: EventCategory?): List<LocalEvent> =
        state.events
            .filter { scope.matches(it) }
            .filter(state::matchesSelectedArea)
            .filter { it.matches(topic) }
            .sortedWith(EventFeedOrdering.discovery)

    companion object {
        fun feedTitle(scope: DateScope, topic: EventCategory?): String {
            val prefix = topic?.let { "${it.shortLabel} · " } ?: ""
            return prefix + when (scope) {
                DateScope.Today -> "What's On Today"
                DateScope.ThisWeek -> "This Week"
                DateScope.ThisMonth -> "This Month"
                DateScope.Upcoming -> "Upcoming"
            }
        }

        fun emptyTitle(scope: DateScope): String = when (scope) {
            DateScope.Today -> "Nothing scheduled here today"
            DateScope.ThisWeek -> "It’s a quiet time right now"
            DateScope.ThisMonth -> "No listings match this month"
            DateScope.Upcoming -> "Nothing coming up in this area"
        }

        fun emptyMessage(scope: DateScope, areaName: String): String =
            if (scope == DateScope.ThisWeek) "List something to be the first thing this week."
            else "Try a wider area or another topic to discover more around $areaName."
    }
}
