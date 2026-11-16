package com.atlasdigital.coastcalendar.feature.hosts

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.atlasdigital.coastcalendar.data.model.MemberNoticeRecord
import com.atlasdigital.coastcalendar.data.repository.UserSession
import com.atlasdigital.coastcalendar.feature.mylistings.PushedScaffold
import com.atlasdigital.coastcalendar.ui.components.EventCard
import com.atlasdigital.coastcalendar.ui.components.FeedMessageCard
import com.atlasdigital.coastcalendar.ui.components.LoadingCard
import com.atlasdigital.coastcalendar.ui.components.PccCard
import com.atlasdigital.coastcalendar.ui.components.PrimaryButton
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val noticeDate = DateTimeFormatter.ofPattern("d MMMM yyyy")

/** iOS `OrganiserEventsScreen`: header, Belong, Notices, then the organisation's listings newest first. */
@Composable
fun OrganisationPageScreen(
    viewModel: OrganisationPageViewModel,
    session: UserSession?,
    onBack: () -> Unit,
    onSignIn: () -> Unit,
    onOpen: (String) -> Unit,
) {
    val state by viewModel.state.collectAsState()
    var showNotices by remember { mutableStateOf(false) }
    LaunchedEffect(session?.userId) { viewModel.bind(session) }

    PushedScaffold("Organisation", onBack) { padding ->
        LazyColumn(
            Modifier.fillMaxSize().padding(padding),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item {
                PccCard {
                    Text(state.name, style = MaterialTheme.typography.headlineSmall)
                    state.profile?.bio?.takeIf { it.isNotBlank() }?.let { Text(it) }
                    if (!state.isLoading) {
                        Text(
                            "${state.events.size} listings · ${state.events.count { it.isPoll }} polls",
                            style = MaterialTheme.typography.labelMedium, color = PccColors.LeafGreen,
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                        PrimaryButton(
                            when {
                                state.followBusy -> "Saving"
                                state.isFollowing -> "You Belong"
                                else -> "Belong"
                            },
                            onClick = { if (session == null) onSignIn() else viewModel.toggleFollow() },
                            modifier = Modifier.weight(1f),
                            enabled = !state.followBusy,
                        )
                        OutlinedButton(onClick = { showNotices = true; viewModel.loadNotices() }, modifier = Modifier.weight(1f)) {
                            Text(if (state.unreadCount > 0 && session != null) "Notices ${state.unreadCount}" else "Notices")
                        }
                    }
                }
            }
            state.actionMessage?.let { msg -> item { Text(msg, color = PccColors.LeafGreen, fontWeight = FontWeight.Bold) } }
            when {
                state.isLoading -> item { LoadingCard("Loading listings") }
                state.error != null -> item { FeedMessageCard("Could not load listings", state.error ?: "", viewModel::load) }
                state.events.isEmpty() -> item { FeedMessageCard("Nothing coming up yet", "${state.name} has no published upcoming listings right now.") }
                else -> {
                    item {
                        Text("Latest from ${state.name}", style = MaterialTheme.typography.titleLarge)
                        Text("Listings and polls are shown newest first.", style = MaterialTheme.typography.bodyMedium)
                    }
                    items(state.events, key = { it.id }) { e -> EventCard(e) { onOpen(e.id) } }
                }
            }
        }
    }

    if (showNotices) NoticesSheet(viewModel, session) { showNotices = false }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NoticesSheet(viewModel: OrganisationPageViewModel, session: UserSession?, onDismiss: () -> Unit) {
    val state by viewModel.state.collectAsState()
    var selected by remember { mutableStateOf<MemberNoticeRecord?>(null) }
    var composing by remember { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = PccColors.Cream) {
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 32.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            when {
                composing -> NoticeComposer(viewModel, state.name) { composing = false }
                selected != null -> {
                    val n = selected!!
                    TextButton(onClick = { selected = null }) { Text("Back to Notices") }
                    Text(n.title, style = MaterialTheme.typography.headlineSmall)
                    Text(noticeDate.format(n.displayDate.atZone(ZoneId.systemDefault())), style = MaterialTheme.typography.labelMedium)
                    n.summary?.takeIf { it.isNotBlank() }?.let { Text(it, fontWeight = FontWeight.Bold) }
                    n.body?.takeIf { it.isNotBlank() }?.let { Text(it) }
                }
                else -> {
                    PccCard {
                        Text("Notices", style = MaterialTheme.typography.headlineMedium)
                        Text("Latest from ${state.name}")
                    }
                    if (viewModel.canCreateNotice) PrimaryButton("Create Notice", { viewModel.clearComposerMessage(); composing = true })
                    if (session != null && state.unreadCount > 0) {
                        TextButton(onClick = { viewModel.markRead(state.notices.map { it.id }) }) {
                            Text("Mark all as read", color = PccColors.LeafGreen, fontWeight = FontWeight.Black)
                        }
                    }
                    when {
                        state.noticesLoading -> LoadingCard("Loading Notices")
                        state.noticesError != null -> FeedMessageCard("Could not load Notices", state.noticesError ?: "", viewModel::loadNotices)
                        state.notices.isEmpty() -> FeedMessageCard("No Notices yet", "${state.name} has not published a Notice or weekly letter yet.")
                        else -> state.notices.forEach { n ->
                            val unread = session != null && n.id.lowercase() !in state.readIds
                            PccCard(onClick = { selected = n; viewModel.markRead(listOf(n.id)) }) {
                                Text(n.title, fontWeight = FontWeight.Black, color = PccColors.Ink, maxLines = 3)
                                Text(
                                    noticeDate.format(n.displayDate.atZone(ZoneId.systemDefault())) + if (unread) " · New" else "",
                                    style = MaterialTheme.typography.labelMedium,
                                )
                                n.summary?.takeIf { it.isNotBlank() }?.let { Text(it, maxLines = 4) }
                                if (n.status != "published") {
                                    Text(n.status.replace('_', ' ').replaceFirstChar { it.uppercase() }, color = PccColors.PohutukawaOrange, fontWeight = FontWeight.Black)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** iOS `MemberNoticeComposerScreen`. */
@Composable
private fun NoticeComposer(viewModel: OrganisationPageViewModel, organiserName: String, onClose: () -> Unit) {
    val state by viewModel.state.collectAsState()
    var title by remember { mutableStateOf("") }
    var summary by remember { mutableStateOf("") }
    var body by remember { mutableStateOf("") }
    TextButton(onClick = onClose) { Text("Cancel") }
    Text("New Notice", style = MaterialTheme.typography.headlineSmall)
    Text("Write a Notice or weekly letter for people who visit $organiserName.")
    OutlinedTextField(title, { title = it }, label = { Text("Title *") }, singleLine = true, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(summary, { summary = it }, label = { Text("Summary") }, placeholder = { Text("A short intro for the Notice list.") }, minLines = 2, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(body, { body = it }, label = { Text("Notice") }, placeholder = { Text("Write the full Notice or weekly letter.") }, minLines = 6, modifier = Modifier.fillMaxWidth())
    state.composerMessage?.let { Text(it, color = PccColors.PohutukawaRed) }
    PrimaryButton(if (state.publishing) "Publishing" else "Publish Notice", { viewModel.publishNotice(title, summary, body, onClose) }, enabled = !state.publishing)
}
