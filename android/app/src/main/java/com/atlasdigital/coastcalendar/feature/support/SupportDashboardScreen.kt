package com.atlasdigital.coastcalendar.feature.support

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.atlasdigital.coastcalendar.data.model.BusinessProfileRecord
import com.atlasdigital.coastcalendar.data.model.BusinessProfileStatus
import com.atlasdigital.coastcalendar.data.model.EventChangeRequestRecord
import com.atlasdigital.coastcalendar.data.model.EventReportStatus
import com.atlasdigital.coastcalendar.data.model.EventReviewReason
import com.atlasdigital.coastcalendar.data.model.ListingStatus
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.data.model.SupportRequestRecord
import com.atlasdigital.coastcalendar.data.model.SupportRequestStatus
import com.atlasdigital.coastcalendar.data.repository.UserSession
import com.atlasdigital.coastcalendar.feature.detail.ListingRemoteImage
import com.atlasdigital.coastcalendar.feature.mylistings.PushedScaffold
import com.atlasdigital.coastcalendar.ui.components.LoadingCard
import com.atlasdigital.coastcalendar.ui.components.PccCard
import com.atlasdigital.coastcalendar.ui.components.PrimaryButton
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import com.atlasdigital.coastcalendar.ui.theme.PccShapes

/** iOS `SupportAdminScreen`: collapsible panels, all collapsed by default. */
@Composable
fun SupportDashboardScreen(viewModel: SupportDashboardViewModel, session: UserSession?, onBack: () -> Unit, onOpen: (String) -> Unit) {
    val state by viewModel.state.collectAsState()
    LaunchedEffect(session?.userId) { viewModel.bind(session) }
    var replying by remember { mutableStateOf<SupportRequestRecord?>(null) }
    var rejecting by remember { mutableStateOf<EventChangeRequestRecord?>(null) }
    var memberAction by remember { mutableStateOf<Pair<BusinessProfileRecord, BusinessProfileStatus>?>(null) }

    PushedScaffold("Support", onBack, actions = { TextButton(onClick = viewModel::load) { Text("Refresh") } }) { padding ->
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(padding).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            PccCard {
                Text("Support Dashboard", style = MaterialTheme.typography.headlineSmall)
                Text("Review member applications, support messages, listings and edit requests.")
            }
            if (state.loading) { LoadingCard("Loading Support data"); return@Column }
            if (state.hasAccess == false) {
                PccCard {
                    Text("Review Queue", style = MaterialTheme.typography.titleLarge)
                    Text("Support tools are only available to authorised listing reviewers.")
                }
                return@Column
            }
            state.actionMessage?.let { Text(it, color = PccColors.LeafGreen, fontWeight = FontWeight.Bold) }
            state.error?.let { Text(it, color = PccColors.PohutukawaRed) }
            if (state.issues.isNotEmpty()) {
                Panel("Support Checks", null, initiallyOpen = true) {
                    state.issues.forEach { Text(it) }
                    PrimaryButton("Try Again", viewModel::load)
                }
            }

            Panel("Support Inbox", state.inbox.size) {
                if (state.inbox.isEmpty()) Text("No support messages yet.")
                state.inbox.forEach { r ->
                    Item {
                        Text("${r.topic} · ${r.requestStatus.label}", fontWeight = FontWeight.Black, color = PccColors.Ink)
                        Text("Reference ${r.id.take(8).uppercase()}", style = MaterialTheme.typography.labelMedium)
                        r.listingReference?.takeIf { it.isNotBlank() }?.let { Text("Listing $it", style = MaterialTheme.typography.labelMedium) }
                        Text(r.message)
                        r.supportNote?.takeIf { it.isNotBlank() }?.let { Text("Support Reply: $it", color = PccColors.LeafGreen) }
                        ActionRow {
                            ActionChip(if (r.supportNote.isNullOrBlank()) "Reply" else "Edit Reply", PccColors.LeafGreen, state.updatingId == r.id) { replying = r }
                            if (r.topic.contains("deletion", ignoreCase = true)) {
                                ActionChip("Complete deletion", PccColors.PohutukawaRed, state.updatingId == r.id) { viewModel.completeDeletion(r) }
                            }
                            ActionChip("Close", PccColors.Text, state.updatingId == r.id) { viewModel.updateRequest(r, SupportRequestStatus.Closed, r.supportNote) }
                        }
                    }
                }
            }

            Panel("Listing Reports", state.openReports.size) {
                if (state.openReports.isEmpty()) Text("No listing reports yet.")
                state.openReports.forEach { rp ->
                    Item {
                        Text("${rp.reportCategory.title} · ${rp.reportStatus.label}", fontWeight = FontWeight.Black, color = PccColors.Ink)
                        Text("Report ${rp.id.take(8).uppercase()} · Listing ${rp.eventId.take(8).uppercase()}", style = MaterialTheme.typography.labelMedium)
                        rp.events?.let { e -> Text("${e.title}", fontWeight = FontWeight.Bold, modifier = Modifier.clickable { onOpen(rp.eventId) }) }
                        Text(rp.details?.takeIf { it.isNotBlank() } ?: "No extra details supplied.")
                        ActionRow {
                            ActionChip("Close", PccColors.LeafGreen, state.updatingId == rp.id) { viewModel.updateReport(rp, EventReportStatus.Closed) }
                            ActionChip("Dismiss", PccColors.Text, state.updatingId == rp.id) { viewModel.updateReport(rp, EventReportStatus.Dismissed) }
                        }
                    }
                }
            }

            Panel("Member Applications", state.applications.size) {
                if (state.applications.isEmpty()) Text("No member applications have been submitted yet.")
                state.applications.forEach { p ->
                    Item {
                        Text(p.businessName, fontWeight = FontWeight.Black, color = PccColors.Ink)
                        Text(listOfNotNull(p.organisationType?.replace('_', ' '), p.areaScopeId).joinToString(" · "), style = MaterialTheme.typography.labelMedium)
                        Text("Email: ${p.contactEmail ?: "Not supplied"}")
                        Text("Contact: ${p.contactName ?: "Not supplied"}")
                        Text("Phone: ${p.phone ?: "Not supplied"}")
                        Text("Website: ${p.website ?: "Not supplied"}")
                        p.about?.takeIf { it.isNotBlank() }?.let { Text(it) }
                        ActionRow {
                            ActionChip("Approve", PccColors.LeafGreen, state.updatingId == p.id) { memberAction = p to BusinessProfileStatus.Approved }
                            ActionChip("Request Changes", PccColors.PohutukawaOrange, state.updatingId == p.id) { memberAction = p to BusinessProfileStatus.Rejected }
                            ActionChip("Suspend", PccColors.PohutukawaRed, state.updatingId == p.id) { memberAction = p to BusinessProfileStatus.Suspended }
                        }
                    }
                }
            }

            Panel("Pending Listings", state.pending.size) {
                if (state.pending.isEmpty()) Text("No pending listings are waiting for review.")
                state.pending.forEach { e ->
                    Item {
                        Text(e.title, fontWeight = FontWeight.Black, color = PccColors.Ink)
                        Text("${e.category.raw} · ${e.displayLocationName}", style = MaterialTheme.typography.labelMedium)
                        if (e.businessProfileId == null) Text("Unverified user listing", color = PccColors.PohutukawaOrange, fontWeight = FontWeight.Bold)
                        Text("Venue: ${e.venue}")
                        Text("Time: ${e.dateText()} · ${e.timeText()}")
                        Text("Price: ${e.priceLabel}")
                        Text("Audience: ${e.audience.ifBlank { "Everyone" }}")
                        Text(e.shortDescription)
                        Text("Review Contact", fontWeight = FontWeight.Bold)
                        Text("Name: ${e.contactName ?: "Not supplied"} · Email: ${e.contactEmail ?: "Not supplied"} · Phone: ${e.contactPhone ?: "Not supplied"}")
                        if (e.images.isNotEmpty()) {
                            Text("Submitted Photos", fontWeight = FontWeight.Bold)
                            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                e.images.forEach { img ->
                                    ListingRemoteImage(img, isPoll = false, modifier = Modifier.size(110.dp).clip(PccShapes.Small))
                                }
                            }
                        }
                        ActionRow {
                            ActionChip("Publish", PccColors.LeafGreen, state.updatingId == e.id) { viewModel.setListingStatus(e, ListingStatus.Published) }
                            ActionChip("Reject", PccColors.PohutukawaRed, state.updatingId == e.id) { viewModel.setListingStatus(e, ListingStatus.Rejected) }
                            ActionChip("Archive", PccColors.Ink, state.updatingId == e.id) { viewModel.setListingStatus(e, ListingStatus.Archived) }
                        }
                    }
                }
            }

            Panel("Change Requests", state.pendingChanges.size) {
                if (state.pendingChanges.isEmpty()) Text("No edit or removal requests are waiting for review.")
                state.pendingChanges.forEach { c ->
                    Item {
                        Text("${c.type.supportTitle} · ${c.events?.title ?: c.eventId.take(8).uppercase()}", fontWeight = FontWeight.Black, color = PccColors.Ink)
                        c.proposedDisplay().forEach { (k, v) -> Text("$k: $v", style = MaterialTheme.typography.bodyMedium) }
                        c.requesterNote?.takeIf { it.isNotBlank() }?.let { Text("Requester Note: $it") }
                        if (c.type == com.atlasdigital.coastcalendar.data.model.EventChangeType.RemovalRequest) {
                            Text("Approving this request archives the listing. It is not permanently deleted.", color = PccColors.PohutukawaOrange)
                        }
                        ActionRow {
                            ActionChip("Apply", PccColors.LeafGreen, state.updatingId == c.id) { viewModel.approveChange(c) }
                            ActionChip("Reject", PccColors.PohutukawaRed, state.updatingId == c.id) { rejecting = c }
                        }
                    }
                }
            }

            EventListPanel("Published Events", state.published, onOpen)
            EventListPanel("Ended", state.ended, onOpen)
            EventListPanel("Rejected", state.rejected, onOpen)
            EventListPanel("Archived", state.archived, onOpen)
            Text(
                "Pending listings and edit requests wait here. Owner remove archives immediately. Published listings stay on the board until dates end or an owner archives them.",
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }

    replying?.let { r -> ReplySheet(r, onDismiss = { replying = null }) { status, note -> viewModel.updateRequest(r, status, note); replying = null } }
    rejecting?.let { c -> RejectSheet(onDismiss = { rejecting = null }) { reason, note -> viewModel.rejectChange(c, reason, note); rejecting = null } }
    memberAction?.let { (p, status) ->
        MemberSheet(p, status, onDismiss = { memberAction = null }) { reason, note -> viewModel.updateMember(p, status, reason, note); memberAction = null }
    }
}

@Composable
private fun Panel(title: String, count: Int?, initiallyOpen: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    var open by rememberSaveable(title) { mutableStateOf(initiallyOpen) }
    PccCard {
        Row(Modifier.fillMaxWidth().clickable { open = !open }, verticalAlignment = Alignment.CenterVertically) {
            Text(title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
            if (count != null) {
                Text(
                    "$count", color = Color.White, fontWeight = FontWeight.Black,
                    modifier = Modifier.clip(CircleShape).background(if (count > 0) PccColors.PohutukawaRed else PccColors.Text.copy(alpha = 0.5f))
                        .padding(horizontal = 10.dp, vertical = 3.dp),
                )
                Spacer(Modifier.width(8.dp))
            }
            Icon(if (open) Icons.Filled.KeyboardArrowUp else Icons.Filled.KeyboardArrowDown, contentDescription = if (open) "Collapse" else "Expand", tint = PccColors.Text)
        }
        AnimatedVisibility(open) { Column(verticalArrangement = Arrangement.spacedBy(10.dp)) { content() } }
    }
}

@Composable
private fun Item(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxWidth().clip(PccShapes.Small).background(Color.White.copy(alpha = 0.75f)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
        content = content,
    )
}

@Composable
private fun ActionRow(content: @Composable () -> Unit) {
    Spacer(Modifier.height(4.dp))
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) { content() }
}

@Composable
private fun ActionChip(title: String, color: Color, updating: Boolean, onClick: () -> Unit) {
    Text(
        if (updating) "Updating" else title,
        color = color, fontWeight = FontWeight.Black,
        modifier = Modifier.clip(PccShapes.Small).background(color.copy(alpha = 0.10f))
            .clickable(enabled = !updating, onClick = onClick).padding(horizontal = 12.dp, vertical = 9.dp),
    )
}

@Composable
private fun EventListPanel(title: String, events: List<LocalEvent>, onOpen: (String) -> Unit) {
    Panel(title, events.size) {
        if (events.isEmpty()) Text("No listings in this section.")
        events.take(100).forEach { e ->
            Item {
                Text(e.title, fontWeight = FontWeight.Bold, color = PccColors.Ink, modifier = Modifier.clickable { onOpen(e.id) })
                Text("${e.displayLocationName} · ${e.venue} · ${e.dateText()}", style = MaterialTheme.typography.labelMedium)
            }
        }
        if (events.size > 100) Text("Showing the first 100 of ${events.size}.")
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReplySheet(request: SupportRequestRecord, onDismiss: () -> Unit, onSave: (SupportRequestStatus, String) -> Unit) {
    var status by remember { mutableStateOf(if (request.requestStatus == SupportRequestStatus.Open) SupportRequestStatus.InReview else request.requestStatus) }
    var note by remember { mutableStateOf(request.supportNote.orEmpty()) }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = PccColors.Cream) {
        Column(Modifier.padding(16.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Reply to Support Request", style = MaterialTheme.typography.headlineSmall)
            Text(request.message)
            Text("Status", style = MaterialTheme.typography.labelMedium)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SupportRequestStatus.entries.forEach { s -> FilterChip(selected = status == s, onClick = { status = s }, label = { Text(s.label) }) }
            }
            OutlinedTextField(note, { note = it }, label = { Text("Reply shown to user") }, minLines = 4, modifier = Modifier.fillMaxWidth())
            PrimaryButton("Save Reply", { onSave(status, note) })
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RejectSheet(onDismiss: () -> Unit, onReject: (EventReviewReason, String) -> Unit) {
    var reason by remember { mutableStateOf(EventReviewReason.NotEnoughInformation) }
    var note by remember { mutableStateOf("") }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = PccColors.Cream) {
        Column(Modifier.padding(16.dp).padding(bottom = 24.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Reject request", style = MaterialTheme.typography.headlineSmall)
            Text("Main reason", style = MaterialTheme.typography.labelMedium)
            EventReviewReason.entries.filter { it != EventReviewReason.ApprovedApplied && it != EventReviewReason.NeedsPayment && it != EventReviewReason.PromotionUpgradeRequired }.forEach { r ->
                FilterChip(selected = reason == r, onClick = { reason = r }, label = { Text(r.label) })
            }
            OutlinedTextField(note, { note = it }, label = { Text("Short note") }, minLines = 3, modifier = Modifier.fillMaxWidth())
            Text("This is shown to the listing owner with the request result.", style = MaterialTheme.typography.bodyMedium)
            PrimaryButton("Reject", { onReject(reason, note) })
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MemberSheet(profile: BusinessProfileRecord, status: BusinessProfileStatus, onDismiss: () -> Unit, onSave: (String?, String?) -> Unit) {
    var reason by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    val needsReason = status != BusinessProfileStatus.Approved
    val title = when (status) {
        BusinessProfileStatus.Approved -> "Approve"
        BusinessProfileStatus.Rejected -> "Request Changes"
        else -> "Suspend"
    }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = PccColors.Cream) {
        Column(Modifier.padding(16.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("$title · ${profile.businessName}", style = MaterialTheme.typography.headlineSmall)
            if (needsReason) OutlinedTextField(reason, { reason = it }, label = { Text("Reason *") }, minLines = 2, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(note, { note = it }, label = { Text("Extra Support note") }, minLines = 2, modifier = Modifier.fillMaxWidth())
            Text("Optional. This can be shown to the member, so keep it clear and professional.", style = MaterialTheme.typography.bodyMedium)
            PrimaryButton(title, { onSave(if (needsReason) reason else null, note) }, enabled = !needsReason || reason.isNotBlank())
            TextButton(onClick = onDismiss) { Text("Cancel") }
        }
    }
}
