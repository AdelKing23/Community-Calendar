package com.atlasdigital.coastcalendar.feature.hosts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.data.model.MemberNoticeRecord
import com.atlasdigital.coastcalendar.data.model.PublicMemberProfileRecord
import com.atlasdigital.coastcalendar.data.remote.ErrorMessages
import com.atlasdigital.coastcalendar.data.repository.UserSession
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class OrganisationPageState(
    val profile: PublicMemberProfileRecord? = null,
    val events: List<LocalEvent> = emptyList(),
    val isLoading: Boolean = true,
    val error: String? = null,
    val isFollowing: Boolean = false,
    val followBusy: Boolean = false,
    val actionMessage: String? = null,
    val ownedProfileId: String? = null,
    val notices: List<MemberNoticeRecord> = emptyList(),
    val noticesLoading: Boolean = false,
    val noticesError: String? = null,
    val readIds: Set<String> = emptySet(),
    val composerMessage: String? = null,
    val publishing: Boolean = false,
) {
    val name: String get() = profile?.displayName?.ifBlank { null } ?: "Organisation"
    val unreadCount: Int get() = notices.count { it.id.lowercase() !in readIds }
}

/** iOS `OrganiserEventsScreen` + `MemberNoticesScreen` + `MemberNoticeComposerScreen` for a public profile. */
class OrganisationPageViewModel(private val container: AppContainer, private val profileId: String) : ViewModel() {
    private val _state = MutableStateFlow(OrganisationPageState())
    val state = _state.asStateFlow()
    private var session: UserSession? = null

    init { load() }

    val canCreateNotice: Boolean
        get() = session != null && _state.value.ownedProfileId?.equals(profileId, ignoreCase = true) == true

    fun bind(s: UserSession?) {
        session = s
        _state.update { it.copy(isFollowing = false, ownedProfileId = null, readIds = emptySet()) }
        if (s == null) return
        viewModelScope.launch {
            runCatching { container.members.isFollowing(profileId, s.userId) }.onSuccess { f -> _state.update { it.copy(isFollowing = f) } }
            runCatching { container.account.businessAccount(s.userId).profile?.id }.onSuccess { id -> _state.update { it.copy(ownedProfileId = id) } }
            loadNotices()
        }
    }

    fun load() {
        _state.update { it.copy(isLoading = it.events.isEmpty(), error = null) }
        viewModelScope.launch {
            val profile = runCatching { container.interactions.publicProfile(profileId) }.getOrNull()
            _state.update { it.copy(profile = profile ?: it.profile) }
            try {
                val events = container.events.profileEvents(profileId).sortedByDescending { it.createdAt }
                container.eventCache.put(events)
                _state.update { it.copy(events = events, isLoading = false) }
            } catch (e: Exception) {
                _state.update { it.copy(isLoading = false, error = ErrorMessages.userFacing(e)) }
            }
        }
    }

    /** iOS `saveFollowState` copy. Signed-out callers are sent to sign in by the screen. */
    fun toggleFollow() {
        val s = session ?: return
        val st = _state.value
        if (st.followBusy) return
        val newValue = !st.isFollowing
        _state.update { it.copy(followBusy = true) }
        viewModelScope.launch {
            try {
                container.members.setFollowing(profileId, s.userId, newValue)
                _state.update {
                    it.copy(
                        isFollowing = newValue, followBusy = false,
                        actionMessage = if (newValue) "You Belong with ${it.name}. Notices can appear in your updates." else "Removed ${it.name} from your Belonging.",
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(followBusy = false, actionMessage = "Belonging could not be saved: ${ErrorMessages.userFacing(e)}") }
            }
        }
    }

    fun loadNotices() {
        _state.update { it.copy(noticesLoading = it.notices.isEmpty(), noticesError = null) }
        viewModelScope.launch {
            try {
                val notices = container.members.notices(profileId, publishedOnly = !canCreateNotice)
                val reads = if (session != null) runCatching { container.members.noticeReads() }.getOrDefault(emptySet()) else emptySet()
                _state.update { it.copy(notices = notices, readIds = reads, noticesLoading = false) }
            } catch (e: Exception) {
                _state.update { it.copy(noticesLoading = false, noticesError = ErrorMessages.userFacing(e)) }
            }
        }
    }

    fun markRead(noticeIds: List<String>) {
        val s = session ?: return
        _state.update { it.copy(readIds = it.readIds + noticeIds.map(String::lowercase)) }
        viewModelScope.launch { noticeIds.forEach { id -> runCatching { container.members.markRead(id, s.userId) } } }
    }

    fun publishNotice(title: String, summary: String, body: String, onDone: () -> Unit) {
        if (title.isBlank()) { _state.update { it.copy(composerMessage = "Add a title before publishing.") }; return }
        val s = session
        if (s == null || !canCreateNotice) { _state.update { it.copy(composerMessage = "Sign in as this member to publish a Notice.") }; return }
        if (_state.value.publishing) return
        _state.update { it.copy(publishing = true, composerMessage = null) }
        viewModelScope.launch {
            try {
                val notice = container.members.createNotice(profileId, s.userId, title, summary, body)
                _state.update { it.copy(publishing = false, notices = listOf(notice) + it.notices) }
                onDone()
            } catch (e: Exception) {
                _state.update { it.copy(publishing = false, composerMessage = ErrorMessages.userFacing(e)) }
            }
        }
    }

    fun clearComposerMessage() = _state.update { it.copy(composerMessage = null) }
}
