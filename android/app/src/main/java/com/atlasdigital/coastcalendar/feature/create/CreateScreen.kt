package com.atlasdigital.coastcalendar.feature.create

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import com.atlasdigital.coastcalendar.data.model.ListingImageStoragePath
import com.atlasdigital.coastcalendar.ui.theme.PccShapes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.atlasdigital.coastcalendar.core.time.PollCloseWindow
import com.atlasdigital.coastcalendar.data.model.CreateKind
import com.atlasdigital.coastcalendar.data.model.EventCategory
import com.atlasdigital.coastcalendar.data.model.ListingRecurrence
import com.atlasdigital.coastcalendar.data.model.PollDetails
import com.atlasdigital.coastcalendar.data.repository.UserSession
import com.atlasdigital.coastcalendar.ui.components.LocationPickerSheet
import com.atlasdigital.coastcalendar.ui.components.PccCard
import com.atlasdigital.coastcalendar.ui.components.PrimaryButton
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import com.atlasdigital.coastcalendar.ui.theme.PccScreenBackground
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

@Composable
fun CreateScreen(
    viewModel: CreateViewModel,
    session: UserSession?,
    contentPadding: PaddingValues,
    onSignIn: () -> Unit,
    onResendVerification: (String) -> Unit,
    onRefreshUser: () -> Unit,
) {
    val state by viewModel.state.collectAsState()
    LaunchedEffect(session?.userId) { viewModel.loadAccount(session) }

    PccScreenBackground {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(
                    start = 16.dp, end = 16.dp,
                    top = contentPadding.calculateTopPadding() + 16.dp,
                    bottom = contentPadding.calculateBottomPadding() + 24.dp,
                ),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Organisation listings", style = MaterialTheme.typography.headlineMedium)
            Text("Only approved Organisations with an active plan can publish listings and polls.", style = MaterialTheme.typography.bodyMedium)

            when {
                session == null -> GateCard(
                    title = "Organisations only",
                    message = "Only approved Organisations can list here. Create an account to register your Organisation.",
                    primary = "Sign in or create account" to onSignIn,
                )
                !session.isEmailVerified -> GateCard(
                    title = "Verify email before member tools",
                    message = "Confirm your email before applying for membership or publishing. This protects listings, receipts and Support follow-up.",
                    primary = "Resend verification email" to { onResendVerification(session.email) },
                    secondary = "Refresh status" to onRefreshUser,
                )
                state.loadingAccount -> GateCard(title = "Checking your Organisation", message = "One moment…")
                !state.account.canSubmitAsOrganisation -> GateCard(
                    title = CreateGate.title(state.account),
                    message = CreateGate.message(state.account),
                    secondary = "Refresh status" to { viewModel.loadAccount(session) },
                )
                state.submittedId != null -> SubmittedCard(state, onCreateAnother = viewModel::createAnother)
                else -> CreateForm(state, viewModel, session)
            }
        }
    }
}

@Composable
private fun GateCard(title: String, message: String, primary: Pair<String, () -> Unit>? = null, secondary: Pair<String, () -> Unit>? = null) {
    PccCard {
        Text(title, style = MaterialTheme.typography.titleLarge)
        Text(message, style = MaterialTheme.typography.bodyMedium)
        primary?.let { (label, action) -> PrimaryButton(label, action) }
        secondary?.let { (label, action) -> OutlinedButton(onClick = action, modifier = Modifier.fillMaxWidth()) { Text(label) } }
    }
}

@Composable
private fun SubmittedCard(state: CreateState, onCreateAnother: () -> Unit) {
    PccCard {
        if (state.submittedKind == CreateKind.Notice) {
            Text("Notice published", style = MaterialTheme.typography.titleLarge)
            Text("“${state.submittedTitle}” is now on your Organisation’s notice board.", style = MaterialTheme.typography.bodyMedium)
        } else {
            Text("Listing Sent for Review", style = MaterialTheme.typography.titleLarge)
            Text(
                "Thanks—your listing is safely in the review queue. We’ll keep it here until Support has checked and published it.",
                style = MaterialTheme.typography.bodyMedium,
            )
            Text("Listing reference: ${state.submittedId?.take(8)}", style = MaterialTheme.typography.labelLarge)
            state.submissionNotice?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = PccColors.PohutukawaRed) }
        }
        PrimaryButton("Create another", onCreateAnother)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CreateForm(state: CreateState, viewModel: CreateViewModel, session: UserSession) {
    val draft = state.draft
    var showLocation by remember { mutableStateOf(false) }

    PccCard {
        Text("Submitting as", style = MaterialTheme.typography.labelLarge)
        Text(state.account.profile?.businessName ?: session.email, style = MaterialTheme.typography.titleLarge)
        if (state.account.isSupport) {
            Text("Support account: creating is free and doesn’t use an allowance.", style = MaterialTheme.typography.bodyMedium, color = PccColors.LeafGreen)
        }
    }

    PccCard {
        Text("What are you creating?", style = MaterialTheme.typography.titleLarge)
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            CreateKind.entries.forEachIndexed { i, k ->
                SegmentedButton(selected = state.kind == k, onClick = { viewModel.setKind(k) }, shape = SegmentedButtonDefaults.itemShape(i, CreateKind.entries.size)) {
                    Text(k.label)
                }
            }
        }
    }

    if (state.kind == CreateKind.Notice) {
        PccCard {
            Field("Title", state.notice.title, "title" in state.missing) { v -> viewModel.updateNotice { it.copy(title = v) } }
            Field("Summary", state.notice.summary, false) { v -> viewModel.updateNotice { it.copy(summary = v) } }
            Field("Notice", state.notice.body, false, singleLine = false) { v -> viewModel.updateNotice { it.copy(body = v) } }
            com.atlasdigital.coastcalendar.ui.components.NoticeDurationPicker(state.notice.days) { d -> viewModel.updateNotice { it.copy(days = d) } }
        }
    } else {
        PccCard {
            Field("Title", draft.title, "title" in state.missing) { v -> viewModel.updateDraft { it.copy(title = v) } }
            CategoryDropdown(draft.category) { c -> viewModel.updateDraft { it.copy(category = c) } }
        }

        ListingPhotoSection(state, viewModel)

        PccCard {
            Text("Location", style = MaterialTheme.typography.titleLarge)
            Text(draft.locationDisplayName, style = MaterialTheme.typography.titleMedium, color = PccColors.LeafGreen)
            OutlinedButton(onClick = { showLocation = true }) { Text("Change place") }
            if (state.kind == CreateKind.Listing) {
                Field("Venue", draft.venue, "venue" in state.missing) { v -> viewModel.updateDraft { it.copy(venue = v) } }
            }
        }

        if (state.kind == CreateKind.Poll) {
            PccCard {
                Text("Poll", style = MaterialTheme.typography.titleLarge)
                Text("Add 2 to 10 answer options. The next answer field appears as people fill them in.", style = MaterialTheme.typography.bodyMedium)
                Field("Question", draft.pollQuestion, "pollQuestion" in state.missing) { v -> viewModel.updateDraft { it.copy(pollQuestion = v) } }
                draft.pollOptions.forEachIndexed { index, option ->
                    Field("Answer ${index + 1}", option, "pollOptions" in state.missing && index < 2 && option.isBlank()) { v ->
                        viewModel.updateDraft { d ->
                            val updated = d.pollOptions.toMutableList().also { it[index] = v }
                            if (updated.last().isNotBlank() && updated.size < PollDetails.MAX_OPTIONS) updated += ""
                            d.copy(pollOptions = updated)
                        }
                    }
                }
                ToggleRow("Allow custom answer", draft.allowsCustomPollAnswer) { on -> viewModel.updateDraft { it.copy(allowsCustomPollAnswer = on) } }
                PollCloseRow(draft.pollClosesAt) { close -> viewModel.updateDraft { it.copy(pollClosesAt = PollCloseWindow.clamp(close)) } }
                Text("The poll opens when it’s published and closes at this time. It then shows as Finished until midnight.", style = MaterialTheme.typography.bodyMedium)
            }
        } else {
            PccCard {
                Text("Date and time", style = MaterialTheme.typography.titleLarge)
                DateRow("Start date (required)", draft.date) { d -> viewModel.updateDraft { it.copy(date = d) } }
                ToggleRow("Add a time", draft.hasTime) { on -> viewModel.updateDraft { it.copy(hasTime = on) } }
                if (draft.hasTime) {
                    TimeRow(draft.time) { t -> viewModel.updateDraft { it.copy(time = t) } }
                } else {
                    Text("No time: this listing shows as All day.", style = MaterialTheme.typography.bodyMedium)
                }
                RecurrenceDropdown(draft.recurrence) { r -> viewModel.updateDraft { it.copy(recurrence = r) } }
                if (draft.recurrence != ListingRecurrence.None) {
                    Text("A repeating listing counts as one listing.", style = MaterialTheme.typography.bodyMedium)
                    ToggleRow("End date", draft.hasRecurrenceEnd) { on -> viewModel.updateDraft { it.copy(hasRecurrenceEnd = on) } }
                    if (draft.hasRecurrenceEnd) {
                        DateRow("Repeats until", draft.recurrenceUntil) { d -> viewModel.updateDraft { it.copy(recurrenceUntil = d) } }
                    }
                }
            }
            PccCard {
                Field("Short description", draft.shortDescription, "description" in state.missing, singleLine = false) { v ->
                    viewModel.updateDraft { it.copy(shortDescription = v) }
                }
                Field("Price", draft.priceLabel, false) { v -> viewModel.updateDraft { it.copy(priceLabel = v) } }
            }
        }

        PccCard {
            Text("Contact", style = MaterialTheme.typography.titleLarge)
            Field("Contact name", draft.contactName, false) { v -> viewModel.updateDraft { it.copy(contactName = v) } }
            Field("Contact email", draft.contactEmail, false) { v -> viewModel.updateDraft { it.copy(contactEmail = v) } }
        }
    }

    state.error?.let { Text(it, color = PccColors.PohutukawaRed, style = MaterialTheme.typography.bodyMedium) }
    PrimaryButton(
        text = when {
            state.submitting -> state.submissionStatus ?: "Sending…"
            state.kind == CreateKind.Notice -> "Publish notice"
            else -> "Send for review"
        },
        enabled = !state.submitting,
        onClick = { viewModel.submit(session) },
    )

    if (showLocation) {
        val selected = state.catalog.scope(draft.locationScopeId) ?: state.catalog.defaultScope(draft.locationScopeId)
        LocationPickerSheet(
            catalog = state.catalog.copy(scopes = state.catalog.listingInputScopes.ifEmpty { state.catalog.scopes }),
            selected = selected,
            onSelect = { viewModel.setLocation(it); showLocation = false },
            onDismiss = { showLocation = false },
        )
    }
}

@Composable
internal fun Field(label: String, value: String, isError: Boolean, singleLine: Boolean = true, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(if (isError) "$label · Required" else label) },
        isError = isError,
        singleLine = singleLine,
        minLines = if (singleLine) 1 else 3,
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
internal fun ToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

private val DATE_LABEL: DateTimeFormatter = DateTimeFormatter.ofPattern("EEE d MMM yyyy")
private val TIME_LABEL: DateTimeFormatter = DateTimeFormatter.ofPattern("h:mm a")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DateRow(label: String, date: LocalDate, onPicked: (LocalDate) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.labelLarge)
            Text(DATE_LABEL.format(date), style = MaterialTheme.typography.titleMedium)
        }
        TextButton(onClick = { open = true }) { Text("Change") }
    }
    if (open) {
        val pickerState = rememberDatePickerState(initialSelectedDateMillis = date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(
            onDismissRequest = { open = false },
            confirmButton = {
                TextButton(onClick = {
                    pickerState.selectedDateMillis?.let { onPicked(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()) }
                    open = false
                }) { Text("OK") }
            },
            dismissButton = { TextButton(onClick = { open = false }) { Text("Cancel") } },
        ) { DatePicker(state = pickerState) }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun TimeRow(time: LocalTime, onPicked: (LocalTime) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text("Start time", style = MaterialTheme.typography.labelLarge)
            Text(TIME_LABEL.format(time), style = MaterialTheme.typography.titleMedium)
        }
        TextButton(onClick = { open = true }) { Text("Change") }
    }
    if (open) {
        val pickerState = rememberTimePickerState(initialHour = time.hour, initialMinute = time.minute, is24Hour = false)
        AlertDialog(
            onDismissRequest = { open = false },
            confirmButton = { TextButton(onClick = { onPicked(LocalTime.of(pickerState.hour, pickerState.minute)); open = false }) { Text("OK") } },
            dismissButton = { TextButton(onClick = { open = false }) { Text("Cancel") } },
            text = { TimePicker(state = pickerState) },
        )
    }
}

@Composable
internal fun PollCloseRow(closesAt: Instant, onPicked: (Instant) -> Unit) {
    val zone = ZoneId.systemDefault()
    val local = closesAt.atZone(zone)
    DateRow("Poll closes on", local.toLocalDate()) { d -> onPicked(d.atTime(local.toLocalTime()).atZone(zone).toInstant()) }
    TimeRow(local.toLocalTime().withSecond(0).withNano(0)) { t -> onPicked(local.toLocalDate().atTime(t).atZone(zone).toInstant()) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CategoryDropdown(selected: EventCategory, onSelect: (EventCategory) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = selected.raw,
            onValueChange = {},
            readOnly = true,
            label = { Text("Category") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
            modifier = Modifier.fillMaxWidth().menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            EventCategory.entries.forEach { c ->
                DropdownMenuItem(text = { Text(c.raw) }, onClick = { onSelect(c); expanded = false })
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RecurrenceDropdown(selected: ListingRecurrence, onSelect: (ListingRecurrence) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = selected.label,
            onValueChange = {},
            readOnly = true,
            label = { Text("Repeats") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
            modifier = Modifier.fillMaxWidth().menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            ListingRecurrence.entries.forEach { r ->
                DropdownMenuItem(text = { Text(r.label) }, onClick = { onSelect(r); expanded = false })
            }
        }
    }
}

/** iOS `ListingPhotoPickerSection`: up to 5 photos, first one leads. */
@Composable
private fun ListingPhotoSection(state: CreateState, viewModel: CreateViewModel) {
    val remaining = (ListingImageStoragePath.MAX_PHOTOS - state.photos.size).coerceAtLeast(0)
    val picker = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.PickMultipleVisualMedia(ListingImageStoragePath.MAX_PHOTOS),
    ) { uris -> viewModel.addPhotos(uris.take(remaining)) }
    PccCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Listing image", style = MaterialTheme.typography.titleLarge)
                Text("Start with a strong photo. You can add up to 5.", style = MaterialTheme.typography.bodyMedium)
            }
            Text("${state.photos.size}/${ListingImageStoragePath.MAX_PHOTOS}", style = MaterialTheme.typography.labelLarge)
        }
        if (state.photos.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                state.photos.forEach { photo ->
                    val bitmap = remember(photo.id) {
                        android.graphics.BitmapFactory.decodeByteArray(photo.data, 0, photo.data.size)?.asImageBitmap()
                    }
                    Box(Modifier.weight(1f).aspectRatio(1f).clip(PccShapes.Small).background(PccColors.Cream)) {
                        bitmap?.let {
                            Image(it, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                        }
                        Text(
                            "✕",
                            color = Color.White,
                            fontWeight = FontWeight.Black,
                            modifier = Modifier.align(Alignment.TopEnd).padding(4.dp).clip(CircleShape)
                                .background(PccColors.Ink.copy(alpha = 0.6f)).clickable(enabled = !state.submitting) { viewModel.removePhoto(photo) }
                                .padding(horizontal = 7.dp, vertical = 2.dp),
                        )
                    }
                }
                repeat(remaining) { Spacer(Modifier.weight(1f)) }
            }
        }
        OutlinedButton(
            onClick = {
                picker.launch(
                    androidx.activity.result.PickVisualMediaRequest(
                        androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia.ImageOnly,
                    ),
                )
            },
            enabled = remaining > 0 && !state.loadingPhotos && !state.submitting,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                when {
                    state.loadingPhotos -> "Preparing Photos"
                    remaining == 0 -> "Maximum Photos Added"
                    state.photos.isEmpty() -> "Upload image or photo"
                    else -> "Add more photos"
                },
            )
        }
    }
}
