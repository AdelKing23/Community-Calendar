package com.atlasdigital.coastcalendar.feature.create

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.data.model.BusinessAccountState
import com.atlasdigital.coastcalendar.data.model.BusinessProfileStatus
import com.atlasdigital.coastcalendar.data.model.CoastTown
import com.atlasdigital.coastcalendar.data.model.CreateKind
import com.atlasdigital.coastcalendar.data.model.ListingDraft
import com.atlasdigital.coastcalendar.data.model.ListingKind
import com.atlasdigital.coastcalendar.data.model.LocationCatalog
import com.atlasdigital.coastcalendar.data.model.LocationScope
import com.atlasdigital.coastcalendar.data.remote.ErrorMessages
import com.atlasdigital.coastcalendar.data.repository.UserSession
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class NoticeDraft(val title: String = "", val summary: String = "", val body: String = "")

data class CreateState(
    val account: BusinessAccountState = BusinessAccountState.Empty,
    val loadingAccount: Boolean = false,
    val catalog: LocationCatalog = LocationCatalog.Local,
    val kind: CreateKind = CreateKind.Listing,
    val draft: ListingDraft = ListingDraft(),
    val notice: NoticeDraft = NoticeDraft(),
    val missing: List<String> = emptyList(),
    val submitting: Boolean = false,
    val error: String? = null,
    val submittedId: String? = null,
    val submittedTitle: String? = null,
    val submittedKind: CreateKind? = null,
)

/** iOS Create gate texts (`createGateTitle` / `createGateMessage`), wording kept free of payment/web references. */
object CreateGate {
    fun title(account: BusinessAccountState): String {
        val profile = account.profile ?: return "Register your Organisation"
        return when (profile.memberStatus) {
            BusinessProfileStatus.PendingReview -> "Organisation pending review"
            BusinessProfileStatus.Approved -> "Subscription required"
            BusinessProfileStatus.Rejected -> "Organisation needs changes"
            BusinessProfileStatus.Suspended -> "Publishing paused"
            BusinessProfileStatus.Archived -> "Organisation archived"
        }
    }

    fun message(account: BusinessAccountState): String {
        val profile = account.profile
            ?: return "Only approved Organisations with an active plan can list here. Organisation registration in the Android app is coming soon."
        return when (profile.memberStatus) {
            BusinessProfileStatus.PendingReview -> "Support is reviewing your Organisation. Listing and polling tools unlock after approval and an active subscription."
            // Android has no plan purchase yet (Play Billing not integrated), so no "choose a subscription in Settings" here.
            BusinessProfileStatus.Approved -> "Your Organisation is approved. An active subscription is needed before you can create listings or polls."
            BusinessProfileStatus.Rejected -> profile.rejectionReason ?: profile.supportNote ?: "Support needs changes before this Organisation can list. Contact Support for the next step."
            BusinessProfileStatus.Suspended -> profile.suspensionReason ?: profile.supportNote ?: "Support has paused publishing for this Organisation. Contact Support."
            BusinessProfileStatus.Archived -> "This Organisation is archived. Contact Support to register again."
        }
    }
}

class CreateViewModel(private val container: AppContainer) : ViewModel() {
    private val _state = MutableStateFlow(CreateState())
    val state: StateFlow<CreateState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            val catalog = if (container.isConfigured) container.locations.catalog() else LocationCatalog.Local
            _state.update { it.copy(catalog = catalog) }
            applySelectedLocation(container.prefs.homeScopeId)
        }
    }

    fun loadAccount(session: UserSession?) {
        if (session == null || !container.isConfigured) {
            _state.update { it.copy(account = BusinessAccountState.Empty, loadingAccount = false) }
            return
        }
        _state.update { it.copy(loadingAccount = true, error = null) }
        viewModelScope.launch {
            val account = runCatching { container.account.businessAccount(session.userId) }.getOrElse { BusinessAccountState.Empty }
            _state.update { it.copy(account = account, loadingAccount = false) }
        }
    }

    /** iOS `applySelectedLocationIfUseful`: start the draft in the area chosen on Home when it is a place. */
    private fun applySelectedLocation(scopeId: String) {
        val scope = _state.value.catalog.scope(scopeId) ?: return
        if (scope.kind != com.atlasdigital.coastcalendar.data.model.LocationScopeKind.Place) return
        setLocation(scope)
    }

    fun setKind(kind: CreateKind) = _state.update {
        it.copy(
            kind = kind,
            draft = it.draft.copy(kind = if (kind == CreateKind.Poll) ListingKind.Poll else ListingKind.Event),
            missing = emptyList(),
            error = null,
        )
    }

    fun updateDraft(transform: (ListingDraft) -> ListingDraft) = _state.update { it.copy(draft = transform(it.draft), missing = emptyList()) }

    fun updateNotice(transform: (NoticeDraft) -> NoticeDraft) = _state.update { it.copy(notice = transform(it.notice), missing = emptyList()) }

    fun setLocation(scope: LocationScope) = updateDraft {
        it.copy(locationScopeId = scope.id, locationDisplayName = scope.name, town = CoastTown.forScopeSlug(scope.id))
    }

    fun submit(session: UserSession?) {
        val s = _state.value
        if (s.submitting || session == null) return
        if (!s.account.canSubmitAsOrganisation) {
            _state.update { it.copy(error = "Only an approved Organisation with an active subscription can submit.") }
            return
        }
        val profileId = s.account.profile?.id ?: run {
            _state.update { it.copy(error = "We couldn’t confirm which member profile this listing belongs to. Refresh your member status and try again.") }
            return
        }
        if (!session.isEmailVerified) {
            _state.update { it.copy(error = "Verify your email before submitting a listing.") }
            return
        }
        val missing = if (s.kind == CreateKind.Notice) {
            if (s.notice.title.isBlank()) listOf("title") else emptyList()
        } else {
            s.draft.missingFields()
        }
        if (missing.isNotEmpty()) {
            _state.update {
                it.copy(missing = missing, error = "Please complete the highlighted required ${if (missing.size == 1) "field" else "fields"}, then submit again.")
            }
            return
        }
        _state.update { it.copy(submitting = true, error = null) }
        viewModelScope.launch {
            try {
                val id = if (s.kind == CreateKind.Notice) {
                    container.listings.createNotice(profileId, session.userId, s.notice.title, s.notice.summary, s.notice.body)
                } else {
                    container.listings.submitPendingListing(s.draft, profileId)
                }
                _state.update {
                    it.copy(
                        submitting = false,
                        submittedId = id,
                        submittedTitle = if (s.kind == CreateKind.Notice) s.notice.title.trim() else s.draft.title.trim(),
                        submittedKind = s.kind,
                        draft = ListingDraft(kind = it.draft.kind, locationScopeId = it.draft.locationScopeId, locationDisplayName = it.draft.locationDisplayName, town = it.draft.town),
                        notice = NoticeDraft(),
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(submitting = false, error = ErrorMessages.userFacing(e)) }
            }
        }
    }

    fun createAnother() = _state.update { it.copy(submittedId = null, submittedTitle = null, submittedKind = null, error = null) }
}
