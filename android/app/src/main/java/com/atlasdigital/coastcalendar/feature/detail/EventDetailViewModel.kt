package com.atlasdigital.coastcalendar.feature.detail

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.core.prefs.AppPreferences.Engagement
import com.atlasdigital.coastcalendar.data.model.EventReportCategory
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.data.model.PollResults
import com.atlasdigital.coastcalendar.data.model.PollUserResponse
import com.atlasdigital.coastcalendar.data.model.PublicMemberProfileRecord
import com.atlasdigital.coastcalendar.data.remote.ErrorMessages
import com.atlasdigital.coastcalendar.data.repository.UserSession
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant

data class PollUiState(
    val results: PollResults = PollResults(),
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
    val poll: PollUiState = PollUiState(),
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

    fun bindSession(session: UserSession?) {
        this.session = session
        if (_state.value.event?.isPoll == true) loadPollState()
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

    // MARK: poll
    private val isClosed: Boolean get() = (_state.value.event?.end ?: Instant.MAX) <= Instant.now()

    private fun updatePoll(transform: (PollUiState) -> PollUiState) = _state.update { it.copy(poll = transform(it.poll)) }

    fun loadPollState() {
        val event = _state.value.event ?: return
        viewModelScope.launch {
            runCatching { container.interactions.pollCounts(event.id) }.onSuccess { r -> updatePoll { it.copy(results = r) } }
            val user = session ?: return@launch
            val mine = runCatching { container.interactions.myPollResponse(event.id, user.userId) }.getOrNull() ?: return@launch
            updatePoll {
                it.copy(
                    selectedOption = mine.displayAnswer,
                    customAnswer = if (mine.isCustomAnswer) mine.customAnswer.orEmpty() else it.customAnswer,
                )
            }
        }
    }

    fun showCustomAnswer() = updatePoll { it.copy(showCustomAnswer = true) }

    fun setCustomAnswer(text: String) =
        updatePoll { it.copy(customAnswer = text.take(com.atlasdigital.coastcalendar.data.model.PollDetails.CUSTOM_ANSWER_LIMIT)) }

    /** iOS `handleOptionTap`: tap the current answer to remove it; switching from Other withdraws first. */
    fun tapOption(option: String) {
        if (isClosed) { updatePoll { it.copy(statusMessage = "This poll is closed.") }; return }
        val current = _state.value.poll.selectedOption
        when (current) {
            option -> withdraw()
            PollUserResponse.CUSTOM_OPTION_LABEL -> viewModelScope.launch {
                withdrawNow()
                submitNow(option, null)
            }
            else -> viewModelScope.launch { submitNow(option, null) }
        }
    }

    fun saveCustomAnswer() {
        val value = _state.value.poll.customAnswer.trim()
        if (value.isEmpty()) withdraw() else viewModelScope.launch { submitNow(null, value) }
    }

    fun withdraw() { viewModelScope.launch { withdrawNow() } }

    private suspend fun withdrawNow() {
        val event = _state.value.event ?: return
        if (session == null) { updatePoll { it.copy(statusMessage = "Sign in to change your answer.") }; return }
        if (isClosed) { updatePoll { it.copy(statusMessage = "This poll is closed.") }; return }
        updatePoll { it.copy(submitting = true, statusMessage = null) }
        try {
            container.interactions.withdrawPollResponse(event.id)
            updatePoll { it.copy(selectedOption = null, customAnswer = "", showCustomAnswer = false, statusMessage = "Answer removed.") }
            loadPollState()
        } catch (e: Exception) {
            updatePoll { it.copy(statusMessage = "Your answer could not be updated. Please try again.") }
        }
        updatePoll { it.copy(submitting = false) }
    }

    private suspend fun submitNow(option: String?, custom: String?) {
        val event = _state.value.event ?: return
        val user = session
        if (user == null) { updatePoll { it.copy(statusMessage = "Sign in to answer this poll.") }; return }
        if (isClosed) { updatePoll { it.copy(statusMessage = "This poll is closed.") }; return }
        if (option.isNullOrBlank() && custom.isNullOrBlank()) return
        updatePoll { it.copy(submitting = true, statusMessage = null) }
        try {
            container.interactions.submitPollResponse(event.id, user.userId, option, custom)
            updatePoll {
                it.copy(
                    selectedOption = option ?: PollUserResponse.CUSTOM_OPTION_LABEL,
                    customAnswer = custom.orEmpty(),
                    showCustomAnswer = false,
                    statusMessage = null,
                )
            }
            loadPollState()
        } catch (e: Exception) {
            updatePoll { it.copy(statusMessage = ErrorMessages.userFacing(e)) }
        }
        updatePoll { it.copy(submitting = false) }
    }

    fun pollStatusText(p: PollUiState = _state.value.poll): String = PollStatus.text(isClosed, p)

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
