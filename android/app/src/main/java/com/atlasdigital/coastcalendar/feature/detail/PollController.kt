package com.atlasdigital.coastcalendar.feature.detail

import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.data.model.PollDetails
import com.atlasdigital.coastcalendar.data.model.PollUserResponse
import com.atlasdigital.coastcalendar.data.remote.ErrorMessages
import com.atlasdigital.coastcalendar.data.repository.UserSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * iOS `PollInlineResponseView` logic, shared by the detail screen and the inline feed card.
 * Same contracts: counts RPC, own row read, upsert on (event_id, respondent_id), delete to withdraw.
 */
class PollController(private val container: AppContainer, private val scope: CoroutineScope, val event: LocalEvent) {
    private val _state = MutableStateFlow(PollUiState())
    val state: StateFlow<PollUiState> = _state.asStateFlow()
    private var session: UserSession? = null
    private var boundOnce = false

    private val isClosed: Boolean get() = event.end <= Instant.now()

    fun bind(s: UserSession?) {
        if (boundOnce && s?.userId == session?.userId) return
        boundOnce = true
        session = s
        if (s == null) _state.update { it.copy(selectedOption = null, customAnswer = "") }
        load()
    }

    fun load() {
        scope.launch {
            runCatching { container.interactions.pollCounts(event.id) }.onSuccess { r -> _state.update { it.copy(results = r) } }
            val user = session ?: return@launch
            val mine = runCatching { container.interactions.myPollResponse(event.id, user.userId) }.getOrNull() ?: return@launch
            _state.update {
                it.copy(selectedOption = mine.displayAnswer, customAnswer = if (mine.isCustomAnswer) mine.customAnswer.orEmpty() else it.customAnswer)
            }
        }
    }

    fun showCustomAnswer() = _state.update { it.copy(showCustomAnswer = true) }
    fun setCustomAnswer(text: String) = _state.update { it.copy(customAnswer = text.take(PollDetails.CUSTOM_ANSWER_LIMIT)) }

    /** iOS `handleOptionTap`: tap the current answer to remove it; switching from Other withdraws first. */
    fun tapOption(option: String) {
        if (isClosed) { _state.update { it.copy(statusMessage = "This poll is closed.") }; return }
        when (_state.value.selectedOption) {
            option -> withdraw()
            PollUserResponse.CUSTOM_OPTION_LABEL -> scope.launch { withdrawNow(); submitNow(option, null) }
            else -> scope.launch { submitNow(option, null) }
        }
    }

    fun saveCustomAnswer() {
        val value = _state.value.customAnswer.trim()
        if (value.isEmpty()) withdraw() else scope.launch { submitNow(null, value) }
    }

    fun withdraw() { scope.launch { withdrawNow() } }

    private suspend fun withdrawNow() {
        if (session == null) { _state.update { it.copy(statusMessage = "Sign in to change your answer.") }; return }
        if (isClosed) { _state.update { it.copy(statusMessage = "This poll is closed.") }; return }
        _state.update { it.copy(submitting = true, statusMessage = null) }
        try {
            container.interactions.withdrawPollResponse(event.id)
            _state.update { it.copy(selectedOption = null, customAnswer = "", showCustomAnswer = false, statusMessage = "Answer removed.") }
            load()
        } catch (e: Exception) {
            _state.update { it.copy(statusMessage = "Your answer could not be updated. Please try again.") }
        }
        _state.update { it.copy(submitting = false) }
    }

    private suspend fun submitNow(option: String?, custom: String?) {
        val user = session
        if (user == null) { _state.update { it.copy(statusMessage = "Sign in to answer this poll.") }; return }
        if (isClosed) { _state.update { it.copy(statusMessage = "This poll is closed.") }; return }
        if (option.isNullOrBlank() && custom.isNullOrBlank()) return
        _state.update { it.copy(submitting = true, statusMessage = null) }
        try {
            container.interactions.submitPollResponse(event.id, user.userId, option, custom)
            _state.update {
                it.copy(selectedOption = option ?: PollUserResponse.CUSTOM_OPTION_LABEL, customAnswer = custom.orEmpty(), showCustomAnswer = false, statusMessage = null)
            }
            load()
        } catch (e: Exception) {
            _state.update { it.copy(statusMessage = ErrorMessages.userFacing(e)) }
        }
        _state.update { it.copy(submitting = false) }
    }

    fun statusText(p: PollUiState = _state.value): String = PollStatus.text(isClosed, p)
}
