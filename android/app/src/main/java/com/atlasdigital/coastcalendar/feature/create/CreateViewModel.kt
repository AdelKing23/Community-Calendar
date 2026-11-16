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
import com.atlasdigital.coastcalendar.data.repository.ListingPhotoUpload
import com.atlasdigital.coastcalendar.data.repository.UserSession
import com.atlasdigital.coastcalendar.core.image.ListingPhotoCompressor
import com.atlasdigital.coastcalendar.data.model.ListingImageStoragePath
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
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
    /** iOS `selectedPhotos`: up to 5 compressed JPEGs, uploaded after the insert in order (position = index + 1). */
    val photos: List<ListingPhotoUpload> = emptyList(),
    val loadingPhotos: Boolean = false,
    val submissionStatus: String? = null,
    val submissionNotice: String? = null,
)

/** iOS Create gate texts (`createGateTitle` / `createGateMessage`), wording kept free of payment/web references. */
object CreateGate {
    fun title(account: BusinessAccountState): String {
        val profile = account.profile ?: return "Register your Organisation"
        return when (profile.memberStatus) {
            BusinessProfileStatus.PendingReview -> "Organisation pending review"
            BusinessProfileStatus.Approved -> "Member access not active"
            BusinessProfileStatus.Rejected -> "Organisation needs changes"
            BusinessProfileStatus.Suspended -> "Publishing paused"
            BusinessProfileStatus.Archived -> "Organisation archived"
        }
    }

    fun message(account: BusinessAccountState): String {
        val profile = account.profile
            ?: return "Only approved Organisations with active member access can list here. Register your Organisation in Settings, then Support reviews it."
        return when (profile.memberStatus) {
            BusinessProfileStatus.PendingReview -> "Support is reviewing your Organisation. Listing and polling tools unlock after approval and once member access is active."
            // Android has no plan purchase yet (Play Billing not integrated), so there is no plan-choice prompt here.
            BusinessProfileStatus.Approved -> "Your Organisation is approved. Member access must be active before you can create listings or polls."
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
            _state.update { it.copy(error = "Only an approved Organisation with active member access can submit.") }
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
                var notice: String? = null
                if (s.kind != CreateKind.Notice && s.photos.isNotEmpty()) {
                    try {
                        s.photos.forEachIndexed { index, photo ->
                            _state.update { it.copy(submissionStatus = "Uploading photo ${index + 1} of ${s.photos.size}") }
                            container.images.uploadListingImage(photo, id, session.userId, position = index + 1)
                        }
                    } catch (e: Exception) {
                        notice = "Your listing was sent for review, but one or more photos could not be uploaded. The text listing is still pending."
                    }
                }
                _state.update {
                    it.copy(
                        submitting = false,
                        submissionStatus = null,
                        submissionNotice = notice,
                        photos = emptyList(),
                        submittedId = id,
                        submittedTitle = if (s.kind == CreateKind.Notice) s.notice.title.trim() else s.draft.title.trim(),
                        submittedKind = s.kind,
                        draft = ListingDraft(kind = it.draft.kind, locationScopeId = it.draft.locationScopeId, locationDisplayName = it.draft.locationDisplayName, town = it.draft.town),
                        notice = NoticeDraft(),
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(submitting = false, submissionStatus = null, error = ErrorMessages.userFacing(e)) }
            }
        }
    }

    fun createAnother() = _state.update { it.copy(submittedId = null, submittedTitle = null, submittedKind = null, submissionNotice = null, error = null) }

    /** iOS `loadPhotos`: stops at 5; a photo that can't be read shows the iOS message. */
    fun addPhotos(uris: List<Uri>) {
        if (uris.isEmpty()) return
        _state.update { it.copy(loadingPhotos = true) }
        viewModelScope.launch {
            for (uri in uris) {
                if (_state.value.photos.size >= ListingImageStoragePath.MAX_PHOTOS) break
                val photo = withContext(Dispatchers.IO) {
                    runCatching { ListingPhotoCompressor.compress(container.appContext.contentResolver, uri) }.getOrNull()
                }
                if (photo != null) {
                    _state.update { it.copy(photos = it.photos + photo) }
                } else {
                    _state.update { it.copy(error = "One photo could not be loaded. Please choose another image.") }
                }
            }
            _state.update { it.copy(loadingPhotos = false) }
        }
    }

    fun removePhoto(photo: ListingPhotoUpload) = _state.update { it.copy(photos = it.photos - photo) }
}
