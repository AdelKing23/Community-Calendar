package com.atlasdigital.coastcalendar.feature.detail

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.core.prefs.AppPreferences.Engagement
import com.atlasdigital.coastcalendar.data.model.EventReportCategory
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.data.model.PublicMemberProfileRecord
import com.atlasdigital.coastcalendar.data.remote.ErrorMessages
import com.atlasdigital.coastcalendar.data.repository.UserSession
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class PollUiState(
    val results: com.atlasdigital.coastcalendar.data.model.PollResults = com.atlasdigital.coastcalendar.data.model.PollResults(),
    val selectedOption: String? = null,
    val customAnswer: String = "",
    val showCustomAnswer: Boolean = false,
    val submitting: Boolean = false,
    val statusMessage: String? = null,
)

data class ReportUiState(
    val category: EventReportCategory = EventReportCategory.WrongOrOutdated,
    val details: String = "",
    val submitting: Boolean = false,
    val didSubmit: Boolean = false,
    val message: String? = null,
)

data class DetailState(
    val event: LocalEvent? = null,
    val profile: PublicMemberProfileRecord? = null,
    val interested: Boolean = false,
    val going: Boolean = false,
    val saved: Boolean = false,
    val report: ReportUiState = ReportUiState(),
)

/** iOS `EventDetailScreen` + `PollInlineResponseView` + `ReportListingSheet` logic. */
class EventDetailViewModel(private val container: AppContainer, eventId: String) : ViewModel() {
    private val _state = MutableStateFlow(DetailState(event = container.eventCache[eventId]))
    val state: StateFlow<DetailState> = _state.asStateFlow()
    private var session: UserSession? = null

    init {
        refreshEngagement()
        val event = _state.value.event
        if (event?.businessProfileId != null) {
            viewModelScope.launch {
                val profile = runCatching { container.interactions.publicProfile(event.businessProfileId) }.getOrNull()
                _state.update { it.copy(profile = profile) }
            }
        }
    }

    /** Poll logic shared with the inline feed card (iOS `PollInlineResponseView`). */
    val poll: PollController? = _state.value.event?.takeIf { it.isPoll }?.let { PollController(container, viewModelScope, it) }

    fun bindSession(session: UserSession?) {
        this.session = session
        poll?.bind(session)
    }

    // MARK: engagement (device-only, iOS EventEngagementStore)
    private fun refreshEngagement() {
        val id = _state.value.event?.id ?: return
        val prefs = container.prefs
        _state.update {
            it.copy(
                interested = prefs.hasEngagement(Engagement.Interested, id),
                going = prefs.hasEngagement(Engagement.Going, id),
                saved = prefs.hasEngagement(Engagement.Saved, id),
            )
        }
    }

    fun toggle(kind: Engagement): Boolean {
        val id = _state.value.event?.id ?: return false
        val on = container.prefs.toggleEngagement(kind, id)
        refreshEngagement()
        return on
    }

    // MARK: report
    private fun updateReport(transform: (ReportUiState) -> ReportUiState) = _state.update { it.copy(report = transform(it.report)) }
    fun setReportCategory(c: EventReportCategory) = updateReport { it.copy(category = c) }
    fun setReportDetails(d: String) = updateReport { it.copy(details = d) }
    fun resetReport() = updateReport { ReportUiState() }

    fun submitReport() {
        val event = _state.value.event ?: return
        if (session == null || _state.value.report.submitting) return
        updateReport { it.copy(submitting = true, message = null) }
        viewModelScope.launch {
            try {
                container.interactions.submitEventReport(event.id, _state.value.report.category, _state.value.report.details)
                updateReport { it.copy(submitting = false, didSubmit = true, details = "", message = "Thanks. Support will review this listing.") }
            } catch (e: Exception) {
                updateReport { it.copy(submitting = false, message = ErrorMessages.userFacing(e)) }
            }
        }
    }
}

/** iOS `PollInlineResponseView.statusText`. */
object PollStatus {
    fun text(isClosed: Boolean, p: PollUiState): String {
        if (isClosed) {
            p.statusMessage?.let { return it }
            p.selectedOption?.let { return "Voting closed. Your answer: $it." }
            return "Voting closed."
        }
        p.statusMessage?.let { return it }
        p.selectedOption?.let { return "Your answer: $it." }
        val total = p.results.totalResponses
        if (total == 0) return "Be the first to answer."
        return "$total response${if (total == 1) "" else "s"} so far."
    }
}
