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
    val photoPreview: ByteArray? = null,
    val photoBusy: Boolean = false,
    val photoMessage: String? = null,
    val removed: Boolean = false,
)

/** iOS `EventDetailScreen` + `PollInlineResponseView` + `ReportListingSheet` logic. */
class EventDetailViewModel(private val container: AppContainer, eventId: String) : ViewModel() {
    private val _state = MutableStateFlow(DetailState(event = container.eventCache[eventId]))
    val state: StateFlow<DetailState> = _state.asStateFlow()
    private var session: UserSession? = null

    init {
        if (_state.value.event == null) {
            // Opened from a reminder or My Calendar without the list cache: read the public listing.
            viewModelScope.launch {
                val loaded = runCatching { container.events.byIds(listOf(eventId)).firstOrNull() }.getOrNull()
                if (loaded != null) {
                    container.eventCache.put(loaded)
                    _state.update { it.copy(event = loaded) }
                    afterEventLoaded()
                }
            }
        } else {
            afterEventLoaded()
        }
    }

    private fun afterEventLoaded() {
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
    private var pollController: PollController? = null
    val poll: PollController?
        get() = pollController ?: _state.value.event?.takeIf { it.isPoll }?.let { e ->
            PollController(container, viewModelScope, e).also { pollController = it; it.bind(session) }
        }

    fun bindSession(session: UserSession?) {
        this.session = session
        poll?.bind(session)
    }

    /** Reminder state for the Plan sheet (device-only, iOS `EventReminderStore`). */
    val reminders get() = container.reminders

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
        val event = _state.value.event ?: return false
        val on = container.prefs.toggleEngagement(kind, event.id)
        if (kind == Engagement.Going) container.reminders.syncGoing(event, on)
        refreshEngagement()
        return on
    }

    // MARK: owner photo + calendar item (iOS canAddPhoto = submitted_by is you; canManageCalendarItem = also org_calendar)
    fun canAddPhoto(): Boolean {
        val uid = session?.userId ?: return false
        return _state.value.event?.submittedBy?.equals(uid, ignoreCase = true) == true
    }

    fun canManageCalendarItem(): Boolean =
        canAddPhoto() && _state.value.event?.status == com.atlasdigital.coastcalendar.data.model.ListingStatus.OrgCalendar

    /** iOS `handlePickedPhoto`: compress, show locally, upload as position 1 (listing-images + event_images). */
    fun addPhoto(uri: android.net.Uri) {
        val event = _state.value.event ?: return
        val user = session ?: return
        if (!canAddPhoto() || _state.value.photoBusy) return
        _state.update { it.copy(photoBusy = true, photoMessage = null) }
        viewModelScope.launch {
            val photo = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                runCatching { com.atlasdigital.coastcalendar.core.image.ListingPhotoCompressor.compress(container.appContext.contentResolver, uri) }.getOrNull()
            }
            if (photo == null) {
                _state.update { it.copy(photoBusy = false, photoMessage = "That photo could not be loaded. Please choose another photo.") }
                return@launch
            }
            _state.update { it.copy(photoPreview = photo.data) }
            try {
                container.images.uploadListingImage(photo, event.id, user.userId, position = 1)
                _state.update { it.copy(photoBusy = false, photoMessage = "Photo saved") }
            } catch (e: Exception) {
                _state.update { it.copy(photoBusy = false, photoMessage = ErrorMessages.userFacing(e)) }
            }
        }
    }

    fun removeCalendarItem() {
        val event = _state.value.event ?: return
        if (!canManageCalendarItem()) return
        viewModelScope.launch {
            try {
                container.ownerListings.archiveOwnListing(event.id)
                _state.update { it.copy(removed = true) }
            } catch (e: Exception) {
                _state.update { it.copy(photoMessage = ErrorMessages.userFacing(e)) }
            }
        }
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
