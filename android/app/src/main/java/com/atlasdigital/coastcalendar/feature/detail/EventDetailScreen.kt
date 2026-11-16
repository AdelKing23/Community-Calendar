package com.atlasdigital.coastcalendar.feature.detail

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Face
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.atlasdigital.coastcalendar.core.calendar.CalendarInsert
import com.atlasdigital.coastcalendar.core.prefs.AppPreferences.Engagement
import com.atlasdigital.coastcalendar.data.model.EventReportCategory
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.data.model.PollDetails
import com.atlasdigital.coastcalendar.data.model.PollUserResponse
import com.atlasdigital.coastcalendar.data.model.PublicMemberProfileRecord
import com.atlasdigital.coastcalendar.data.repository.UserSession
import com.atlasdigital.coastcalendar.ui.components.PccCard
import com.atlasdigital.coastcalendar.ui.components.PrimaryButton
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import com.atlasdigital.coastcalendar.ui.theme.PccScreenBackground
import com.atlasdigital.coastcalendar.ui.theme.PccShapes
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** iOS `EventDetailScreen`: event or poll layout, organiser card, engagement row, report panel. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EventDetailScreen(
    viewModel: EventDetailViewModel,
    session: UserSession?,
    onBack: () -> Unit,
    onSignIn: () -> Unit,
    onOpenOrganisation: (String) -> Unit = {},
) {
    val state by viewModel.state.collectAsState()
    val context = LocalContext.current
    var showReport by remember { mutableStateOf(false) }
    var showPlan by remember { mutableStateOf(false) }
    var showOrganiser by remember { mutableStateOf(false) }
    LaunchedEffect(session?.userId) { viewModel.bindSession(session) }
    LaunchedEffect(state.removed) { if (state.removed) onBack() }
    val event = state.event

    Scaffold(
        containerColor = PccColors.Cream,
        topBar = {
            TopAppBar(
                title = { Text(if (event?.isPoll == true) "Poll" else "Event", fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.White.copy(alpha = 0.96f), titleContentColor = PccColors.Ink),
            )
        },
    ) { padding ->
        PccScreenBackground {
            if (event == null) {
                Column(Modifier.padding(padding).padding(16.dp)) {
                    PccCard {
                        Text("This listing isn’t available", style = MaterialTheme.typography.titleLarge)
                        Text("It may have finished or been removed. Go back and refresh the board.")
                    }
                }
                return@PccScreenBackground
            }
            Column(
                verticalArrangement = Arrangement.spacedBy(18.dp),
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(padding)
                    .padding(horizontal = 16.dp, vertical = 16.dp),
            ) {
                val engagement: @Composable () -> Unit = {
                    PccCard {
                        EngagementRow(
                            interested = state.interested,
                            going = state.going,
                            saved = state.saved,
                            onInterested = { viewModel.toggle(Engagement.Interested) },
                            onGoing = { if (viewModel.toggle(Engagement.Going)) showPlan = true },
                            onSave = { viewModel.toggle(Engagement.Saved) },
                            onShare = { share(context, event) },
                        )
                    }
                }
                if (event.isPoll) {
                    PollHero(event)
                    PccCard {
                        InfoRow(Icons.Filled.DateRange, "Closes", closeText(event))
                        InfoRow(Icons.Filled.LocationOn, "Area", event.displayLocationName)
                        InfoRow(Icons.Filled.AccountCircle, "Asked by", event.organiserDisplayName)
                    }
                    val details = event.pollDetails
                    val pollController = viewModel.poll
                    if (details != null && pollController != null) {
                        PccCard {
                            Text("Cast your answer", style = MaterialTheme.typography.labelMedium, color = PccColors.PohutukawaOrange)
                            PollResponsePanel(details, pollController)
                        }
                    } else {
                        PccCard { Text("This poll is being prepared. Check back shortly to have your say.") }
                    }
                    if (event.businessProfileId != null) OrganiserPanel(event, state.profile) { showOrganiser = true }
                    PccCard {
                        Text("Why this poll is running", style = MaterialTheme.typography.titleLarge)
                        Text(event.publicLongDescription.ifBlank { "No extra context was added." })
                    }
                    engagement()
                } else {
                    val photoPicker = androidx.activity.compose.rememberLauncherForActivityResult(
                        androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia(),
                    ) { uri -> if (uri != null) viewModel.addPhoto(uri) }
                    EventHero(
                        event,
                        canAddPhoto = viewModel.canAddPhoto(),
                        preview = state.photoPreview,
                        busy = state.photoBusy,
                        message = state.photoMessage,
                    ) {
                        photoPicker.launch(androidx.activity.result.PickVisualMediaRequest(androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia.ImageOnly))
                    }
                    if (viewModel.canManageCalendarItem()) {
                        var confirmRemove by remember { mutableStateOf(false) }
                        TextButton(onClick = { confirmRemove = true }, modifier = Modifier.fillMaxWidth()) {
                            Text("Remove from calendar", color = PccColors.PohutukawaRed, fontWeight = FontWeight.Bold)
                        }
                        if (confirmRemove) {
                            androidx.compose.material3.AlertDialog(
                                onDismissRequest = { confirmRemove = false },
                                title = { Text("Remove this date?") },
                                text = { Text("It comes off your organisation calendar. Support can restore it if needed.") },
                                confirmButton = { TextButton(onClick = { confirmRemove = false; viewModel.removeCalendarItem() }) { Text("Remove", color = PccColors.PohutukawaRed) } },
                                dismissButton = { TextButton(onClick = { confirmRemove = false }) { Text("Cancel") } },
                            )
                        }
                    }
                    PccCard {
                        InfoRow(Icons.Filled.DateRange, "Date", event.dateText())
                        InfoRow(Icons.Filled.Refresh, "Time", event.timeText())
                        val venue = "${event.venue}, ${event.displayLocationName}"
                        InfoRow(Icons.Filled.Place, "Venue", venue) { openMaps(context, venue) }
                        InfoRow(Icons.Filled.ShoppingCart, "Cost", event.priceLabel)
                        if (event.audience.isNotBlank()) InfoRow(Icons.Filled.Face, "Good for", event.audience)
                    }
                    if (event.businessProfileId != null) OrganiserPanel(event, state.profile) { showOrganiser = true }
                    PccCard {
                        Text("About this event", style = MaterialTheme.typography.titleLarge)
                        Text(event.publicLongDescription, style = MaterialTheme.typography.bodyLarge)
                    }
                    val email = event.contactEmail?.trim().orEmpty()
                    val phone = event.contactPhone?.trim().orEmpty()
                    if (email.isNotEmpty() || phone.isNotEmpty()) {
                        PccCard {
                            Text("Public Contact", style = MaterialTheme.typography.titleLarge)
                            if (email.isNotEmpty()) Text(email, fontWeight = FontWeight.SemiBold)
                            if (phone.isNotEmpty()) Text(phone, fontWeight = FontWeight.SemiBold)
                        }
                    }
                    engagement()
                    ReportPanel { showReport = true }
                }
            }
        }
    }

    if (showReport && event != null) {
        ReportSheet(event, state.report, session != null, viewModel, onSignIn = { showReport = false; onSignIn() }) {
            showReport = false
            viewModel.resetReport()
        }
    }
    if (showPlan && event != null) {
        PlanSheet(event, viewModel.reminders, onAddToCalendar = { addToCalendar(context, event) }, onNotGoing = {
            viewModel.toggle(Engagement.Going); showPlan = false
        }) { showPlan = false }
    }
    if (showOrganiser && event != null) {
        OrganiserSheet(event, state.profile, onOpenPage = {
            showOrganiser = false
            event.businessProfileId?.let(onOpenOrganisation)
        }) { showOrganiser = false }
    }
}

private fun closeText(event: LocalEvent): String =
    DateTimeFormatter.ofPattern("EEEE d MMMM yyyy, h:mm a").format(event.end.atZone(ZoneId.systemDefault()))

@Composable
private fun EventHero(
    event: LocalEvent,
    canAddPhoto: Boolean = false,
    preview: ByteArray? = null,
    busy: Boolean = false,
    message: String? = null,
    onAddPhoto: () -> Unit = {},
) {
    PccCard {
        Box(Modifier.let { if (canAddPhoto) it.clickable(onClick = onAddPhoto) else it }) {
            if (preview != null) {
                coil3.compose.AsyncImage(
                    model = preview, contentDescription = "Listing photo", contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 190.dp, max = 260.dp).clip(PccShapes.Small),
                )
            } else {
                ListingRemoteImage(event.primaryImage, isPoll = false, modifier = Modifier.heightIn(min = 190.dp))
            }
            if (canAddPhoto && preview == null && event.primaryImage == null) {
                Text(
                    "Add photo", color = Color.White, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black),
                    modifier = Modifier.align(Alignment.BottomEnd).padding(12.dp).clip(CircleShape).background(PccColors.LeafGreen)
                        .padding(horizontal = 10.dp, vertical = 6.dp),
                )
            }
            if (busy) CircularProgressIndicator(Modifier.align(Alignment.Center).size(28.dp), color = PccColors.LeafGreen)
            if (event.isFinished()) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.align(Alignment.TopStart).padding(12.dp).clip(CircleShape)
                        .background(PccColors.Ink.copy(alpha = 0.78f)).padding(horizontal = 10.dp, vertical = 6.dp),
                ) {
                    Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = Color.White, modifier = Modifier.size(14.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Finished", color = Color.White, style = MaterialTheme.typography.labelMedium)
                }
            }
        }
        message?.let { Text(it, color = if (it == "Photo saved") PccColors.LeafGreen else PccColors.PohutukawaRed, fontWeight = FontWeight.Bold) }
        if (event.images.size > 1) ImageStrip(event)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(event.category.raw.uppercase(), style = MaterialTheme.typography.labelMedium, color = PccColors.PohutukawaOrange)
            Spacer(Modifier.weight(1f))
            Capsule(event.displayLocationName, PccColors.LeafGreen.copy(alpha = 0.08f), PccColors.LeafGreen)
        }
        Text(event.title, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Black, fontSize = 34.sp, color = PccColors.Ink, lineHeight = 38.sp)
        if (event.shortDescription.isNotBlank()) Text(event.shortDescription, style = MaterialTheme.typography.bodyLarge)
        if (event.isPromoted) Capsule(event.promotionBadgeTitle, PccColors.LeafGreen, Color.White)
    }
}

@Composable
private fun ImageStrip(event: LocalEvent) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        event.images.drop(1).take(4).forEach { image ->
            ListingRemoteImage(image, isPoll = false, modifier = Modifier.weight(1f).heightIn(min = 64.dp, max = 90.dp),
                contentScale = androidx.compose.ui.layout.ContentScale.Crop)
        }
        repeat((4 - (event.images.size - 1)).coerceAtLeast(0)) { Spacer(Modifier.weight(1f)) }
    }
}

@Composable
private fun PollHero(event: LocalEvent) {
    PccCard {
        ListingRemoteImage(event.primaryImage, isPoll = true)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Capsule("Poll", PccColors.LeafGreen, Color.White)
            Text(event.category.shortLabel, style = MaterialTheme.typography.labelMedium, color = PccColors.PohutukawaOrange)
            Spacer(Modifier.weight(1f))
            Capsule(event.displayLocationName, PccColors.LeafGreen.copy(alpha = 0.08f), PccColors.LeafGreen)
        }
        Text(event.title, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Black, fontSize = 30.sp, color = PccColors.Ink, lineHeight = 34.sp)
        if (event.shortDescription.isNotBlank()) Text(event.shortDescription, style = MaterialTheme.typography.bodyLarge)
    }
}

/** iOS `PollInlineResponseView`. */
@Composable
internal fun PollResponsePanel(details: PollDetails, viewModel: PollController) {
    val poll by viewModel.state.collectAsState()
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.fillMaxWidth().clip(PccShapes.Small).background(PccColors.LeafGreen.copy(alpha = 0.07f)).padding(12.dp),
    ) {
        Text(details.question, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black), color = PccColors.Ink)
        details.options.forEach { option ->
            PollOptionButton(
                title = option,
                count = poll.results.count(option),
                total = poll.results.totalResponses,
                selected = poll.selectedOption == option,
                enabled = !poll.submitting,
            ) { viewModel.tapOption(option) }
        }
        if (details.allowsCustomAnswer) {
            val other = PollUserResponse.CUSTOM_OPTION_LABEL
            PollOptionButton(
                title = other,
                subtitle = if (poll.selectedOption == other) "Edit your answer" else "Type your own answer",
                count = poll.results.count(other),
                total = poll.results.totalResponses,
                selected = poll.selectedOption == other,
                enabled = !poll.submitting,
            ) { viewModel.showCustomAnswer() }
            if (poll.showCustomAnswer) {
                Column(Modifier.clip(PccShapes.Small).background(PccColors.Cream.copy(alpha = 0.54f)).padding(10.dp)) {
                    OutlinedTextField(
                        value = poll.customAnswer,
                        onValueChange = viewModel::setCustomAnswer,
                        placeholder = { Text("Your answer") },
                        minLines = 2,
                        maxLines = 4,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("${poll.customAnswer.length}/${PollDetails.CUSTOM_ANSWER_LIMIT}", style = MaterialTheme.typography.labelMedium)
                        Spacer(Modifier.weight(1f))
                        TextButton(onClick = viewModel::saveCustomAnswer, enabled = !poll.submitting) {
                            Text("Save", color = PccColors.LeafGreen, fontWeight = FontWeight.Black)
                        }
                    }
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (poll.submitting) {
                CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp, color = PccColors.LeafGreen)
                Spacer(Modifier.width(8.dp))
            }
            val status = viewModel.statusText(poll)
            Text(
                status,
                style = MaterialTheme.typography.labelLarge,
                color = if (status.contains("could not", ignoreCase = true)) PccColors.PohutukawaRed else PccColors.Text,
            )
        }
    }
}

@Composable
private fun OrganiserPanel(event: LocalEvent, profile: PublicMemberProfileRecord?, onOpen: () -> Unit) {
    val name = profile?.displayName?.trim()?.takeIf { it.isNotEmpty() } ?: event.organiserDisplayName
    PccCard(onClick = onOpen) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(54.dp).clip(CircleShape).background(PccColors.LeafGreen), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.AccountCircle, contentDescription = null, tint = Color.White, modifier = Modifier.size(30.dp))
            }
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("Listed by", style = MaterialTheme.typography.labelMedium, color = PccColors.Text)
                Text(name, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Black), maxLines = 2)
                Text("Tap to view this Organisation", style = MaterialTheme.typography.bodyMedium)
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = PccColors.PohutukawaOrange)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun OrganiserSheet(event: LocalEvent, profile: PublicMemberProfileRecord?, onOpenPage: () -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = PccColors.Cream) {
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(profile?.displayName?.ifBlank { null } ?: event.organiserDisplayName, style = MaterialTheme.typography.headlineSmall)
            profile?.bio?.takeIf { it.isNotBlank() }?.let { Text(it, style = MaterialTheme.typography.bodyLarge) }
            PccCard {
                Text("Public contact", style = MaterialTheme.typography.titleLarge)
                val email = profile?.publicContactEmail?.trim().orEmpty()
                val phone = profile?.publicPhone?.trim().orEmpty()
                val address = profile?.publicAddress?.trim().orEmpty()
                val website = profile?.publicWebsite?.trim().orEmpty()
                if (email.isNotEmpty()) InfoRow(Icons.Filled.Email, "Email", email) { open(context, "mailto:$email") }
                if (phone.isNotEmpty()) InfoRow(Icons.Filled.Phone, "Phone", phone) {
                    open(context, "tel:" + phone.filter { it == '+' || it.isDigit() })
                }
                if (address.isNotEmpty()) InfoRow(Icons.Filled.Place, "Address", address) { openMaps(context, address) }
                if (website.isNotEmpty()) InfoRow(Icons.Filled.Info, "Website", website) {
                    open(context, if (website.contains("://")) website else "https://$website")
                }
                if (email.isEmpty() && phone.isEmpty() && address.isEmpty() && website.isEmpty()) {
                    Text("No public contact details have been published for this organiser yet.")
                }
                Text("These details are supplied by the listing owner and reviewed before publication.", style = MaterialTheme.typography.bodyMedium)
            }
            if (profile != null) {
                com.atlasdigital.coastcalendar.ui.components.PrimaryButton("Open Organisation page", onOpenPage)
            }
        }
    }
}

@Composable
private fun ReportPanel(onReport: () -> Unit) {
    PccCard {
        Text("Something not right?", style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black), color = PccColors.Ink)
        Text("Report a listing if it looks unsafe, misleading, spammy or out of date. Reports go privately to Support.")
        Row(
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().clip(PccShapes.Small).background(PccColors.PohutukawaRed.copy(alpha = 0.10f))
                .clickable(onClick = onReport).padding(vertical = 12.dp),
        ) {
            Icon(Icons.Filled.Warning, contentDescription = null, tint = PccColors.PohutukawaRed, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text("Report this listing", color = PccColors.PohutukawaRed, fontWeight = FontWeight.Black)
        }
    }
}

/** iOS `ReportListingSheet`. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReportSheet(
    event: LocalEvent,
    report: ReportUiState,
    signedIn: Boolean,
    viewModel: EventDetailViewModel,
    onSignIn: () -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = PccColors.Cream) {
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Report", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                TextButton(onClick = onDismiss) { Text(if (report.didSubmit) "Done" else "Cancel", color = PccColors.PohutukawaRed) }
            }
            PccCard {
                Text("REPORT LISTING", style = MaterialTheme.typography.labelMedium, color = PccColors.PohutukawaRed)
                Text(event.title, style = MaterialTheme.typography.titleLarge)
                Text("Tell Support what needs checking. Your report is private and is not shown to the organiser or public users.")
                if (!signedIn) {
                    TextButton(onClick = onSignIn) { Text("Sign in to send a private report", color = PccColors.PohutukawaRed, fontWeight = FontWeight.Bold) }
                } else {
                    var expanded by remember { mutableStateOf(false) }
                    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
                        OutlinedTextField(
                            value = report.category.title,
                            onValueChange = {},
                            readOnly = true,
                            label = { Text("Reason") },
                            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
                            modifier = Modifier.fillMaxWidth().menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
                        )
                        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                            EventReportCategory.entries.forEach { c ->
                                DropdownMenuItem(text = { Text(c.title) }, onClick = { viewModel.setReportCategory(c); expanded = false })
                            }
                        }
                    }
                    Text("Optional details", style = MaterialTheme.typography.labelMedium)
                    OutlinedTextField(
                        value = report.details,
                        onValueChange = viewModel::setReportDetails,
                        minLines = 4,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
            report.message?.let {
                PccCard {
                    Text(if (report.didSubmit) "Report sent" else "Report not sent", style = MaterialTheme.typography.titleMedium, color = PccColors.Ink)
                    Text(it)
                }
            }
            if (signedIn && !report.didSubmit) {
                PrimaryButton(if (report.submitting) "Sending report" else "Send report", onClick = viewModel::submitReport, enabled = !report.submitting)
            }
        }
    }
}

/** iOS `EventPlanSheet` (Going): reminder alarm + device calendar add. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PlanSheet(
    event: LocalEvent,
    reminders: com.atlasdigital.coastcalendar.core.reminders.EventReminderStore,
    onAddToCalendar: () -> Unit,
    onNotGoing: () -> Unit,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = PccColors.Cream) {
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Going", style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                TextButton(onClick = onDismiss) { Text("Done", color = PccColors.PohutukawaRed) }
            }
            PccCard {
                Text("PLAN THIS", style = MaterialTheme.typography.labelMedium, color = PccColors.PohutukawaOrange)
                Text(event.title, style = MaterialTheme.typography.titleLarge)
                Text("${event.dateText()} · ${event.timeText()}\n${event.venue}, ${event.displayLocationName}")
            }
            ReminderCard(event, reminders)
            PccCard {
                Text("Device calendar", style = MaterialTheme.typography.titleMedium, color = PccColors.Ink)
                Text("Add this listing to your phone’s calendar.")
                PrimaryButton("Add to Calendar", onClick = onAddToCalendar)
            }
            TextButton(onClick = onNotGoing, modifier = Modifier.fillMaxWidth()) { Text("Not going", color = PccColors.Text, fontWeight = FontWeight.Bold) }
        }
    }
}

private fun share(context: Context, event: LocalEvent) {
    val text = "${event.title}\n${event.dateText()}\n${event.timeText()}\n${event.venue}, ${event.displayLocationName}\n\nShared from Coast Calendar."
    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
    context.startActivity(Intent.createChooser(send, null))
}

private fun addToCalendar(context: Context, event: LocalEvent) {
    try { context.startActivity(CalendarInsert.of(event).toIntent()) } catch (_: ActivityNotFoundException) { }
}

private fun openMaps(context: Context, address: String) = open(context, "geo:0,0?q=" + Uri.encode(address))

private fun open(context: Context, uri: String) {
    try { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri))) } catch (_: ActivityNotFoundException) { }
}


/** iOS "Reminder alarm": pick a lead time, Set reminder (asks for notification permission on Android 13+), Remove. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReminderCard(event: LocalEvent, reminders: com.atlasdigital.coastcalendar.core.reminders.EventReminderStore) {
    val context = LocalContext.current
    var lead by remember(event.id) { mutableStateOf(reminders.leadTime(event.id)) }
    var has by remember(event.id) { mutableStateOf(reminders.hasReminder(event.id)) }
    var needsSettings by remember { mutableStateOf(false) }
    var message by remember(event.id) { mutableStateOf(if (reminders.hasReminder(event.id)) "Reminder set for ${reminders.leadTime(event.id).title.lowercase()}." else null) }
    var expanded by remember { mutableStateOf(false) }

    fun apply() {
        when (reminders.schedule(event, lead)) {
            is com.atlasdigital.coastcalendar.core.reminders.ScheduleResult.Scheduled -> {
                has = true; needsSettings = false; message = "Reminder set for ${lead.title.lowercase()}."
            }
            com.atlasdigital.coastcalendar.core.reminders.ScheduleResult.Denied -> {
                needsSettings = true; message = "Notifications are off for Coast Calendar. Turn them on in Android Settings to get reminders."
            }
            com.atlasdigital.coastcalendar.core.reminders.ScheduleResult.Unavailable -> {
                has = false; message = "This listing starts too soon for a reminder."
            }
        }
    }
    val permission = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission(),
    ) { granted -> if (granted) apply() else { needsSettings = true; message = "Notifications are off for Coast Calendar. Turn them on in Android Settings to get reminders." } }

    PccCard {
        Text(if (has) "Reminder alarm · on" else "Reminder alarm", style = MaterialTheme.typography.titleMedium, color = PccColors.Ink)
        androidx.compose.material3.ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
            androidx.compose.material3.OutlinedTextField(
                value = lead.title, onValueChange = {}, readOnly = true, label = { Text("Reminder time") },
                modifier = Modifier.fillMaxWidth().menuAnchor(androidx.compose.material3.ExposedDropdownMenuAnchorType.PrimaryNotEditable),
            )
            ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                com.atlasdigital.coastcalendar.core.reminders.ReminderLeadTime.entries.forEach { option ->
                    androidx.compose.material3.DropdownMenuItem(text = { Text(option.title) }, onClick = { lead = option; expanded = false })
                }
            }
        }
        message?.let { Text(it, color = if (needsSettings) PccColors.PohutukawaOrange else PccColors.LeafGreen, fontWeight = FontWeight.Bold) }
        PrimaryButton(if (needsSettings) "Open notification settings" else "Set reminder", onClick = {
            if (needsSettings) {
                val intent = Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName)
                try { context.startActivity(intent) } catch (_: ActivityNotFoundException) { }
                needsSettings = false
            } else if (android.os.Build.VERSION.SDK_INT >= 33 && !reminders.notificationsAllowed() &&
                androidx.core.content.ContextCompat.checkSelfPermission(context, android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED
            ) {
                permission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
            } else {
                apply()
            }
        })
        TextButton(onClick = { reminders.cancel(event.id); has = false; needsSettings = false; message = "Reminder removed." }, enabled = has, modifier = Modifier.fillMaxWidth()) {
            Text("Remove reminder", color = PccColors.Text, fontWeight = FontWeight.Bold)
        }
    }
}
