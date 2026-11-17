package com.atlasdigital.coastcalendar.feature.support

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.data.model.BusinessProfileRecord
import com.atlasdigital.coastcalendar.data.model.BusinessProfileStatus
import com.atlasdigital.coastcalendar.data.model.EventChangeRequestRecord
import com.atlasdigital.coastcalendar.data.model.EventReportRecord
import com.atlasdigital.coastcalendar.data.model.EventReportStatus
import com.atlasdigital.coastcalendar.data.model.EventReviewReason
import com.atlasdigital.coastcalendar.data.model.ListingStatus
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.data.model.SupportRequestRecord
import com.atlasdigital.coastcalendar.data.model.SupportRequestStatus
import com.atlasdigital.coastcalendar.data.model.supportLabel
import com.atlasdigital.coastcalendar.data.model.supportSortPriority
import com.atlasdigital.coastcalendar.data.repository.CompleteAccountDeletion
import com.atlasdigital.coastcalendar.data.repository.UserSession
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant

data class SupportDashboardState(
    val loading: Boolean = true,
    val hasAccess: Boolean? = null,
    val events: List<LocalEvent> = emptyList(),
    val profiles: List<BusinessProfileRecord> = emptyList(),
    val changeRequests: List<EventChangeRequestRecord> = emptyList(),
    val requests: List<SupportRequestRecord> = emptyList(),
    val reports: List<EventReportRecord> = emptyList(),
    val issues: List<String> = emptyList(),
    val updatingId: String? = null,
    val actionMessage: String? = null,
    val error: String? = null,
) {
    private val now get() = Instant.now()
    val inbox get() = requests.filter { it.requestStatus == SupportRequestStatus.Open || it.requestStatus == SupportRequestStatus.InReview }
        .sortedWith(compareBy<SupportRequestRecord> { it.requestStatus.ordinal }.thenByDescending { it.created })
    val openReports get() = reports.filter { it.reportStatus == EventReportStatus.Open || it.reportStatus == EventReportStatus.InReview }
        .sortedWith(compareBy<EventReportRecord> { it.reportStatus.sortPriority }.thenByDescending { it.created })
    val applications get() = profiles.filter { it.memberStatus == BusinessProfileStatus.PendingReview }
        .sortedWith(compareBy<BusinessProfileRecord> { it.memberStatus.supportSortPriority })
    val pending get() = events.filter { it.status == ListingStatus.PendingReview }.sortedByDescending { it.createdAt }
    val pendingChanges get() = changeRequests.filter { it.isPending }.sortedByDescending { it.created }
    val published get() = events.filter { it.status == ListingStatus.Published && it.end > now }.sortedBy { it.start }
    val ended get() = events.filter { it.status == ListingStatus.Published && it.end <= now }.sortedByDescending { it.end }
    val rejected get() = events.filter { it.status == ListingStatus.Rejected }.sortedByDescending { it.createdAt }
    val archived get() = events.filter { it.status == ListingStatus.Archived }.sortedByDescending { it.createdAt }
}

/** iOS `SupportAdminScreen` loader + actions (same RPCs / PATCHes). */
class SupportDashboardViewModel(private val container: AppContainer) : ViewModel() {
    private val _state = MutableStateFlow(SupportDashboardState())
    val state = _state.asStateFlow()
    private var session: UserSession? = null
    private val repo get() = container.supportAdmin

    fun bind(s: UserSession?) { session = s; load() }

    fun load() {
        if (session == null) { _state.value = SupportDashboardState(loading = false, hasAccess = false); return }
        _state.update { it.copy(loading = it.events.isEmpty(), error = null) }
        viewModelScope.launch {
            val access = runCatching { repo.isSupport() }.getOrDefault(false)
            if (!access) { _state.update { it.copy(loading = false, hasAccess = false) }; return@launch }
            val issues = mutableListOf<String>()
            coroutineScope {
                val events = async { runCatching { repo.allEvents() }.onFailure { issues += "Listings could not load." }.getOrNull() }
                val profiles = async { runCatching { repo.memberProfiles() }.onFailure { issues += "Member applications could not load." }.getOrNull() }
                val changes = async { runCatching { repo.changeRequests() }.onFailure { issues += "Change requests could not load." }.getOrNull() }
                val requests = async { runCatching { repo.supportRequests() }.onFailure { issues += "Support inbox could not load." }.getOrNull() }
                val reports = async { runCatching { repo.eventReports() }.onFailure { issues += "Listing reports could not load." }.getOrNull() }
                val e = events.await(); val p = profiles.await(); val c = changes.await(); val r = requests.await(); val rp = reports.await()
                _state.update {
                    it.copy(
                        loading = false, hasAccess = true, issues = issues.toList(),
                        events = e ?: it.events, profiles = p ?: it.profiles, changeRequests = c ?: it.changeRequests,
                        requests = r ?: it.requests, reports = rp ?: it.reports,
                    )
                }
            }
        }
    }

    private fun act(id: String, failure: String, block: suspend () -> String) {
        if (_state.value.updatingId != null) return
        _state.update { it.copy(updatingId = id, actionMessage = null, error = null) }
        viewModelScope.launch {
            try {
                val msg = block()
                _state.update { it.copy(updatingId = null, actionMessage = msg) }
                load()
            } catch (e: Exception) {
                _state.update { it.copy(updatingId = null, error = failure) }
            }
        }
    }

    fun setListingStatus(event: LocalEvent, status: ListingStatus) =
        act(event.id, "Could not update this listing. If your session expired, sign out and sign in again.") {
            repo.moderateListing(event.id, status); "${event.title} moved to ${status.supportLabel}."
        }

    fun approveChange(request: EventChangeRequestRecord) =
        act(request.id, "Could not apply this request. If your session expired, sign out and sign in again.") {
            repo.approveChangeRequest(request, EventReviewReason.ApprovedApplied, null); "${request.type.supportTitle} applied."
        }

    fun rejectChange(request: EventChangeRequestRecord, reason: EventReviewReason, note: String?) =
        act(request.id, "Could not reject this request. If your session expired, sign out and sign in again.") {
            repo.rejectChangeRequest(request.id, reason, note); "${request.type.supportTitle} rejected."
        }

    fun updateRequest(request: SupportRequestRecord, status: SupportRequestStatus, note: String?) =
        act(request.id, "Could not update this support request. If your session expired, sign out and sign in again.") {
            repo.updateSupportRequest(request.id, status, note); "Support request ${request.id.take(8).uppercase()} updated."
        }

    /** iOS 5a067ca: edge function `complete-account-deletion` (login + photos removed server-side). */
    fun completeDeletion(request: SupportRequestRecord) {
        if (_state.value.updatingId != null) return
        _state.update { it.copy(updatingId = request.id, actionMessage = null, error = null) }
        viewModelScope.launch {
            try {
                repo.completeAccountDeletion(request.id, CompleteAccountDeletion.SUPPORT_NOTE)
                _state.update { it.copy(updatingId = null, actionMessage = CompleteAccountDeletion.SUCCESS) }
            } catch (e: Exception) {
                val status = (e as? io.github.jan.supabase.exceptions.RestException)?.statusCode
                android.util.Log.w("SupportHQ", "complete deletion failed (status ${status ?: "none"})")
                _state.update { it.copy(updatingId = null, error = CompleteAccountDeletion.failureMessage(status)) }
            }
            load()
        }
    }

    fun updateReport(report: EventReportRecord, status: EventReportStatus) =
        act(report.id, "Could not update this listing report. If your session expired, sign out and sign in again.") {
            repo.updateEventReport(report.id, status); "Listing report ${report.id.take(8).uppercase()} moved to ${status.label}."
        }

    fun updateMember(profile: BusinessProfileRecord, status: BusinessProfileStatus, reason: String?, note: String?) =
        act(profile.id, "Could not update this member profile. If your session expired, sign out and sign in again.") {
            repo.transitionMember(profile.id, status, reason, note)
            "${profile.businessName} moved to ${status.raw.replace('_', ' ').replaceFirstChar { it.uppercase() }}."
        }
}
