package com.atlasdigital.coastcalendar.feature.detail

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.core.prefs.AppPreferences.Engagement
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.ui.components.Chip
import com.atlasdigital.coastcalendar.ui.components.LocalAppContainer
import com.atlasdigital.coastcalendar.ui.components.LocalUserSession
import com.atlasdigital.coastcalendar.ui.components.PccCard
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import com.atlasdigital.coastcalendar.ui.theme.PccShapes

class PollCardViewModel(container: AppContainer, event: LocalEvent) : ViewModel() {
    val controller = PollController(container, viewModelScope, event)
}

/**
 * iOS `PollFeedCard`: header, organiser, title, image, "Poll closes …", inline voting (same RPCs), then
 * Open Poll · Save · Share. Returns false when it can't render inline (no container or no poll details).
 */
@Composable
fun PollFeedCard(event: LocalEvent, onOpen: () -> Unit): Boolean {
    val container = LocalAppContainer.current ?: return false
    val details = event.pollDetails ?: return false
    val session = LocalUserSession.current
    val vm: PollCardViewModel = viewModel(key = "poll-card-${event.id}") { PollCardViewModel(container, event) }
    LaunchedEffect(session?.userId) { vm.controller.bind(session) }
    var saved by remember(event.id) { mutableStateOf(container.prefs.hasEngagement(Engagement.Saved, event.id)) }
    val context = LocalContext.current

    PccCard {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            Chip("Poll", PccColors.LeafGreen, Color.White)
            Chip(event.category.shortLabel, PccColors.PohutukawaOrange, Color.White)
            Text(event.displayLocationName, style = MaterialTheme.typography.labelMedium, color = PccColors.LeafGreen, maxLines = 1,
                overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        }
        Text(event.organiserDisplayName, style = MaterialTheme.typography.labelLarge, color = PccColors.Text, maxLines = 1)
        Text(event.title, style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Black), color = PccColors.Ink, maxLines = 3,
            modifier = Modifier.clickable(onClick = onOpen))
        if (event.shortDescription.isNotBlank()) Text(event.shortDescription, style = MaterialTheme.typography.bodyMedium, maxLines = 3)
        ListingRemoteImage(event.primaryImage, isPoll = true, modifier = Modifier.height(118.dp).clip(PccShapes.Small), contentScale = ContentScale.Crop)
        Text("Poll closes ${event.dateText()}", style = MaterialTheme.typography.labelMedium)
        Text("Asked by ${event.organiserDisplayName}", style = MaterialTheme.typography.labelMedium)
        PollResponsePanel(details, vm.controller)
        Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            PollAction("Open Poll", false, Modifier.weight(1f), onOpen)
            PollAction("Save", saved, Modifier.weight(1f)) { saved = container.prefs.toggleEngagement(Engagement.Saved, event.id) }
            PollAction("Share", false, Modifier.weight(1f)) {
                val text = "Poll: ${event.title}\n${event.displayLocationName}\nShared from Coast Calendar."
                context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text), null))
            }
        }
    }
    return true
}

@Composable
private fun PollAction(title: String, selected: Boolean, modifier: Modifier, onClick: () -> Unit) {
    Text(
        title, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Black),
        color = PccColors.LeafGreen, maxLines = 1,
        modifier = modifier.clip(PccShapes.Small)
            .background(if (selected) PccColors.LeafGreen.copy(alpha = 0.12f) else PccColors.Cream.copy(alpha = 0.66f))
            .clickable(onClick = onClick).padding(vertical = 10.dp, horizontal = 6.dp),
        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
    )
}
