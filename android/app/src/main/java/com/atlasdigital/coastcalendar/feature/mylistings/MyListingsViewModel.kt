package com.atlasdigital.coastcalendar.feature.mylistings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.data.model.EventChangeRequestRecord
import com.atlasdigital.coastcalendar.data.model.EventChangeRequestStatus
import com.atlasdigital.coastcalendar.data.model.ListingEditDraft
import com.atlasdigital.coastcalendar.data.model.ListingStatus
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.data.repository.UserSession
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class MyListingsState(
    val listings: List<LocalEvent> = emptyList(),
    val changeRequests: List<EventChangeRequestRecord> = emptyList(),
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val actionMessage: String? = null,
    val submitting: Boolean = false,
) {
    fun requests(listing: LocalEvent) = changeRequests.filter { it.eventId.equals(listing.id, true) }.sortedByDescending { it.created }
    fun pendingRequest(listing: LocalEvent) = requests(listing).firstOrNull { it.isPending }
    fun latestRequest(listing: LocalEvent) = requests(listing).firstOrNull()
    fun canRemove(listing: LocalEvent) = pendingRequest(listing) == null && listing.status != ListingStatus.Archived
    fun needsAction(listing: LocalEvent) =
        listing.status != ListingStatus.Archived && latestRequest(listing)?.requestStatus == EventChangeRequestStatus.Rejected
}

/** iOS `MyListingsSettingsScreen` logic. */
class MyListingsViewModel(private val container: AppContainer) : ViewModel() {
    private val _state = MutableStateFlow(MyListingsState())
    val state: StateFlow<MyListingsState> = _state.asStateFlow()
    private var session: UserSession? = null

    fun bind(session: UserSession?) {
        if (session?.userId == this.session?.userId && _state.value.listings.isNotEmpty()) return
        this.session = session
        load()
    }

    fun load() {
        val user = session
        if (user == null) {
            _state.value = MyListingsState()
            return
        }
        _state.update { it.copy(isLoading = it.listings.isEmpty(), errorMessage = null) }
        viewModelScope.launch {
            try {
                val listings = async { container.ownerListings.userListings(user.userId) }
                val requests = async { container.ownerListings.myChangeRequests(user.userId) }
                val l = listings.await()
                val r = requests.await()
                if (session?.userId != user.userId) return@launch
                container.eventCache.put(l)
                _state.update { it.copy(listings = l, changeRequests = r, isLoading = false) }
            } catch (e: Exception) {
                _state.update { it.copy(isLoading = false, errorMessage = "Your listings could not be loaded. Please try again soon.") }
            }
        }
    }

    fun submitEdit(listing: LocalEvent, draft: ListingEditDraft, note: String?, onDone: () -> Unit) {
        val user = session ?: return
        _state.update { it.copy(submitting = true) }
        viewModelScope.launch {
            try {
                container.ownerListings.createEditRequest(listing, draft, user.userId, note)
                _state.update { it.copy(submitting = false, actionMessage = "Edit request sent for ${listing.title}.") }
                onDone()
                load()
            } catch (e: Exception) {
                _state.update { it.copy(submitting = false, actionMessage = "Edit request could not be sent. Please try again.") }
            }
        }
    }

    fun remove(listing: LocalEvent, onDone: () -> Unit) {
        if (session == null) return
        _state.update { it.copy(submitting = true) }
        viewModelScope.launch {
            try {
                container.ownerListings.archiveOwnListing(listing.id)
                _state.update { it.copy(submitting = false, actionMessage = "${listing.title} is off the public board.") }
                onDone()
                load()
            } catch (e: Exception) {
                _state.update { it.copy(submitting = false, actionMessage = "Could not remove this listing. Please try again.") }
            }
        }
    }
}
