package com.atlasdigital.coastcalendar.feature.mylistings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.atlasdigital.coastcalendar.core.time.PollCloseWindow
import com.atlasdigital.coastcalendar.data.model.EventChangeRequestRecord
import com.atlasdigital.coastcalendar.data.model.ListingEditDraft
import com.atlasdigital.coastcalendar.data.model.ListingStatus
import com.atlasdigital.coastcalendar.data.model.ListingStatusCopy
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.data.repository.UserSession
import com.atlasdigital.coastcalendar.feature.create.CategoryDropdown
import com.atlasdigital.coastcalendar.feature.create.DateRow
import com.atlasdigital.coastcalendar.feature.create.Field
import com.atlasdigital.coastcalendar.feature.create.PollCloseRow
import com.atlasdigital.coastcalendar.feature.create.TimeRow
import com.atlasdigital.coastcalendar.feature.create.ToggleRow
import com.atlasdigital.coastcalendar.feature.detail.Capsule
import com.atlasdigital.coastcalendar.feature.detail.ListingRemoteImage
import com.atlasdigital.coastcalendar.ui.components.FeedMessageCard
import com.atlasdigital.coastcalendar.ui.components.LoadingCard
import com.atlasdigital.coastcalendar.ui.components.PccCard
import com.atlasdigital.coastcalendar.ui.components.PrimaryButton
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import com.atlasdigital.coastcalendar.ui.theme.PccScreenBackground
import com.atlasdigital.coastcalendar.ui.theme.PccShapes

/** Back-arrow top bar shared by pushed screens (Settings sub-pages). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PushedScaffold(title: String, onBack: () -> Unit, actions: @Composable () -> Unit = {}, content: @Composable (androidx.compose.foundation.layout.PaddingValues) -> Unit) {
    Scaffold(
        containerColor = PccColors.Cream,
        topBar = {
            TopAppBar(
                title = { Text(title, fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") } },
                actions = { actions() },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.White.copy(alpha = 0.96f), titleContentColor = PccColors.Ink),
            )
        },
    ) { padding -> PccScreenBackground { content(padding) } }
}

/** iOS `MyListingsSettingsScreen` + `MyListingsPanel`. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MyListingsScreen(viewModel: MyListingsViewModel, session: UserSession?, onBack: () -> Unit, onSignIn: () -> Unit, onOpen: (String) -> Unit) {
    val state by viewModel.state.collectAsState()
    LaunchedEffect(session?.userId) { viewModel.bind(session) }
    var viewing by remember { mutableStateOf<LocalEvent?>(null) }
    var editing by remember { mutableStateOf<LocalEvent?>(null) }
    var removing by remember { mutableStateOf<LocalEvent?>(null) }

    PushedScaffold("My Listings", onBack, actions = {
        IconButton(onClick = viewModel::load) { Icon(Icons.Filled.Refresh, contentDescription = "Refresh", tint = PccColors.LeafGreen) }
    }) { padding ->
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            PccCard {
                Text("My Listings", fontFamily = FontFamily.Serif, fontWeight = FontWeight.Black, fontSize = 36.sp, color = PccColors.Ink)
                Text("Listings you can manage stay here with Support feedback attached.")
            }
            if (session == null) {
                PccCard {
                    Text("Sign in to manage listings", style = MaterialTheme.typography.titleLarge)
                    Text("Sign in here to see submitted, pending, approved and archived listings.")
                    PrimaryButton("Sign in", onSignIn)
                }
                return@Column
            }
            state.actionMessage?.let { PccCard { Text(it, color = PccColors.LeafGreen, fontWeight = FontWeight.Bold) } }
            when {
                state.isLoading -> LoadingCard("Loading your listings")
                state.errorMessage != null -> FeedMessageCard("My Listings", state.errorMessage!!, viewModel::load)
                state.listings.isEmpty() -> PccCard { Text("Listings you can manage will appear here after they are sent for review.") }
                else -> state.listings.forEach { listing ->
                    ListingRow(
                        listing = listing,
                        pending = state.pendingRequest(listing),
                        latest = state.latestRequest(listing),
                        needsAction = state.needsAction(listing),
                        canRemove = state.canRemove(listing),
                        onView = { viewing = listing },
                        onEdit = { editing = listing },
                        onRemove = { removing = listing },
                    )
                }
            }
        }
    }

    viewing?.let { listing ->
        ListingViewSheet(listing, state.requests(listing), state.pendingRequest(listing) != null,
            onOpenPublic = { viewing = null; onOpen(listing.id) },
            onEdit = { viewing = null; editing = listing },
            onRemove = { viewing = null; removing = listing },
        ) { viewing = null }
    }
    editing?.let { listing ->
        EditRequestSheet(listing, state.submitting, onSubmit = { draft, note -> viewModel.submitEdit(listing, draft, note) { editing = null } }) { editing = null }
    }
    removing?.let { listing ->
        RemoveSheet(listing, state.submitting, onConfirm = { viewModel.remove(listing) { removing = null } }) { removing = null }
    }
}

@Composable
private fun statusTint(status: ListingStatus): Color = when (status) {
    ListingStatus.Published -> PccColors.LeafGreen
    ListingStatus.Rejected -> PccColors.PohutukawaRed
    ListingStatus.PendingReview, ListingStatus.ApprovedAwaitingPayment -> PccColors.PohutukawaOrange
    else -> PccColors.Text
}

@Composable
private fun ListingRow(
    listing: LocalEvent,
    pending: EventChangeRequestRecord?,
    latest: EventChangeRequestRecord?,
    needsAction: Boolean,
    canRemove: Boolean,
    onView: () -> Unit,
    onEdit: () -> Unit,
    onRemove: () -> Unit,
) {
    PccCard {
        ListingRemoteImage(listing.primaryImage, listing.isPoll, Modifier.height(120.dp), ContentScale.Crop)
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(listing.title, style = MaterialTheme.typography.titleLarge, maxLines = 2)
                Text(
                    if (listing.isPoll) "${listing.displayLocationName} · Poll closes ${java.time.format.DateTimeFormatter.ofPattern("EEEE d MMMM, h:mm a").format(listing.end.atZone(java.time.ZoneId.systemDefault()))}"
                    else "${listing.displayLocationName} · ${listing.venue}",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            Capsule(ListingStatusCopy.userLabel(listing.status), statusTint(listing.status).copy(alpha = 0.12f), statusTint(listing.status))
        }
        if (!listing.isPoll) Text("${listing.dateText()} · ${listing.timeText()}", style = MaterialTheme.typography.labelLarge, color = PccColors.Text)
        Text(ListingStatusCopy.ownerNote(listing.status), style = MaterialTheme.typography.bodyMedium)
        when {
            pending != null -> Text("${pending.type.supportTitle} pending support review", color = PccColors.PohutukawaOrange, fontWeight = FontWeight.Bold)
            needsAction -> Text("Action needed: tap View to read Support feedback", color = PccColors.PohutukawaRed, fontWeight = FontWeight.Bold)
            latest != null && listing.status != ListingStatus.Archived -> Text(latest.userSummary, color = PccColors.LeafGreen, fontWeight = FontWeight.Bold)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            OutlinedButton(onClick = onView, modifier = Modifier.weight(1f)) { Text("View") }
            OutlinedButton(onClick = onEdit, enabled = pending == null, modifier = Modifier.weight(1f)) { Text("Edit") }
            if (listing.status == ListingStatus.Archived) {
                Text("Archived", modifier = Modifier.weight(1f).padding(top = 10.dp), color = PccColors.Text, fontWeight = FontWeight.Bold)
            } else {
                OutlinedButton(onClick = onRemove, enabled = canRemove, modifier = Modifier.weight(1f)) {
                    Text("Remove", color = if (canRemove) PccColors.PohutukawaRed else PccColors.Text)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ListingViewSheet(
    listing: LocalEvent,
    requests: List<EventChangeRequestRecord>,
    hasPending: Boolean,
    onOpenPublic: () -> Unit,
    onEdit: () -> Unit,
    onRemove: () -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = PccColors.Cream) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            PccCard {
                Capsule(ListingStatusCopy.userLabel(listing.status), statusTint(listing.status).copy(alpha = 0.12f), statusTint(listing.status))
                Text(listing.title, style = MaterialTheme.typography.headlineSmall)
                if (listing.shortDescription.isNotBlank()) Text(listing.shortDescription)
                if (listing.status == ListingStatus.Rejected && requests.none { !it.supportNote.isNullOrBlank() }) {
                    Text("Needs work", color = PccColors.PohutukawaRed, fontWeight = FontWeight.Black)
                    Text("Support did not approve this listing. There is no extra written reason on file. Edit and send it back, or Remove to archive it.")
                }
            }
            PccCard {
                if (listing.isPoll) {
                    Info("Closes", java.time.format.DateTimeFormatter.ofPattern("EEEE d MMMM yyyy, h:mm a").format(listing.end.atZone(java.time.ZoneId.systemDefault())))
                    Info("Area", listing.displayLocationName)
                    Info("Asked by", listing.organiserDisplayName)
                } else {
                    Info("Date", listing.dateText())
                    Info("Time", listing.timeText())
                    Info("Location", "${listing.venue}, ${listing.displayLocationName}")
                    Info("Price", listing.priceLabel)
                    if (listing.audience.isNotBlank()) Info("Audience", listing.audience)
                }
            }
            if (requests.isNotEmpty()) {
                PccCard {
                    Text("Support history", style = MaterialTheme.typography.titleLarge)
                    requests.forEach { r ->
                        Column(Modifier.fillMaxWidth().clip(PccShapes.Small).background(Color.White.copy(alpha = 0.7f)).padding(10.dp)) {
                            Text(r.userSummary, fontWeight = FontWeight.Bold, color = PccColors.Ink)
                            r.supportNote?.takeIf { it.isNotBlank() }?.let { Text(it) }
                            r.requesterNote?.takeIf { it.isNotBlank() }?.let { Text("Your note: $it", style = MaterialTheme.typography.bodyMedium) }
                        }
                    }
                }
            }
            Text(if (hasPending) "Request already waiting for review." else "Changes go back through review.", style = MaterialTheme.typography.bodyMedium)
            if (listing.status == ListingStatus.Published) OutlinedButton(onClick = onOpenPublic, modifier = Modifier.fillMaxWidth()) { Text("Open public listing") }
            Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                OutlinedButton(onClick = onEdit, enabled = !hasPending, modifier = Modifier.weight(1f)) { Text("Edit") }
                if (listing.status != ListingStatus.Archived) {
                    OutlinedButton(onClick = onRemove, enabled = !hasPending, modifier = Modifier.weight(1f)) { Text("Remove", color = PccColors.PohutukawaRed) }
                }
            }
        }
    }
}

@Composable
private fun Info(title: String, value: String) {
    Column {
        Text(title, style = MaterialTheme.typography.labelMedium, color = PccColors.Text)
        Text(value, fontWeight = FontWeight.Bold, color = PccColors.Ink)
    }
}

/** iOS `ListingEditRequestSheet`: sends a change request; the public listing does not change until Support applies it. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun EditRequestSheet(listing: LocalEvent, submitting: Boolean, onSubmit: (ListingEditDraft, String?) -> Unit, onDismiss: () -> Unit) {
    var draft by remember(listing.id) { mutableStateOf(ListingEditDraft.from(listing)) }
    var note by remember(listing.id) { mutableStateOf("") }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = PccColors.Cream) {
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Edit Request", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                TextButton(onClick = onDismiss) { Text("Cancel", color = PccColors.PohutukawaRed) }
            }
            PccCard {
                Text("Request an edit", style = MaterialTheme.typography.headlineSmall)
                Text("Your public listing will not change until Support reviews this request.")
            }
            PccCard {
                Field("Event Name", draft.title, draft.title.isBlank()) { v -> draft = draft.copy(title = v) }
                Field("Venue", draft.venue, draft.venue.isBlank()) { v -> draft = draft.copy(venue = v) }
                CategoryDropdown(draft.category) { c -> draft = draft.copy(category = c) }
                if (draft.isPoll) {
                    PollCloseRow(draft.pollClosesAt) { close ->
                        val r = draft.pollCloseRange()
                        draft = draft.copy(pollClosesAt = minOf(maxOf(close, r.start), r.endInclusive))
                    }
                    Text("Poll closes 1 hour to ${PollCloseWindow.MAXIMUM_DAYS} days after it opened.", style = MaterialTheme.typography.bodyMedium)
                } else {
                    DateRow("Date", draft.date) { d -> draft = draft.copy(date = d) }
                    ToggleRow("Add a time", draft.hasTime) { on -> draft = draft.copy(hasTime = on) }
                    if (draft.hasTime) TimeRow(draft.time) { t -> draft = draft.copy(time = t) } else Text("No time: this listing shows as All day.", style = MaterialTheme.typography.bodyMedium)
                }
                Field("Cost", draft.priceLabel, false) { v -> draft = draft.copy(priceLabel = v) }
                Field("Audience", draft.audience, false) { v -> draft = draft.copy(audience = v) }
                Field("Contact Name", draft.contactName, false) { v -> draft = draft.copy(contactName = v) }
                Field("Contact Email", draft.contactEmail, false) { v -> draft = draft.copy(contactEmail = v) }
                Field("Contact Phone", draft.contactPhone, false) { v -> draft = draft.copy(contactPhone = v) }
                Field("Short Description", draft.shortDescription, draft.shortDescription.isBlank(), singleLine = false) { v -> draft = draft.copy(shortDescription = v) }
                Field("Extra details", draft.longDescription, false, singleLine = false) { v -> draft = draft.copy(longDescription = v) }
                OutlinedTextField(value = note, onValueChange = { note = it }, label = { Text("Note (optional)") }, minLines = 2, modifier = Modifier.fillMaxWidth())
                Text("To replace a listing photo, include the requested change in your note for Support.", style = MaterialTheme.typography.bodyMedium)
            }
            PrimaryButton(if (submitting) "Sending Request" else "Send Edit Request", onClick = { onSubmit(draft, note) }, enabled = draft.canSubmit && !submitting)
            Spacer(Modifier.height(8.dp))
        }
    }
}

/** iOS `ListingRemovalRequestSheet` (build 11: archives straight away through `owner_archive_own_listing`). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RemoveSheet(listing: LocalEvent, submitting: Boolean, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = PccColors.Cream) {
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Remove Listing", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                TextButton(onClick = onDismiss) { Text("Cancel", color = PccColors.PohutukawaRed) }
            }
            PccCard {
                Text("Remove this listing?", style = MaterialTheme.typography.headlineSmall)
                Text(listing.title, style = MaterialTheme.typography.titleMedium, color = PccColors.Ink)
                Text("It will come off the public board. Support can restore it if this was a mistake. Poll answers and listing history stay on file.")
            }
            androidx.compose.material3.Button(
                onClick = onConfirm,
                enabled = !submitting,
                modifier = Modifier.fillMaxWidth(),
                colors = androidx.compose.material3.ButtonDefaults.buttonColors(containerColor = PccColors.PohutukawaRed),
            ) { Text(if (submitting) "Removing" else "Remove listing", fontWeight = FontWeight.Bold) }
        }
    }
}
