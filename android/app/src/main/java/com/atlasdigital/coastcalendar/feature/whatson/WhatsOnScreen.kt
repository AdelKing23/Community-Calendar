package com.atlasdigital.coastcalendar.feature.whatson

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.atlasdigital.coastcalendar.data.model.DateScope
import com.atlasdigital.coastcalendar.data.model.EventCategory
import com.atlasdigital.coastcalendar.ui.components.AreaButton
import com.atlasdigital.coastcalendar.ui.components.Chip
import com.atlasdigital.coastcalendar.ui.components.EventCard
import com.atlasdigital.coastcalendar.ui.components.FeedMessageCard
import com.atlasdigital.coastcalendar.ui.components.LoadingCard
import com.atlasdigital.coastcalendar.ui.components.LocationPickerSheet
import com.atlasdigital.coastcalendar.ui.components.PccCard
import com.atlasdigital.coastcalendar.ui.components.ScopeChipRow
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import com.atlasdigital.coastcalendar.ui.theme.PccScreenBackground

/** iOS What's On: header, Today/Week/Month/Upcoming tabs, Browse by topic, area control, then the feed. */
@Composable
fun WhatsOnScreen(viewModel: WhatsOnViewModel, contentPadding: PaddingValues) {
    val state by viewModel.state.collectAsState()
    val scope by viewModel.dateScope.collectAsState()
    val topic by viewModel.topic.collectAsState()
    var showPicker by remember { mutableStateOf(false) }
    val visible = viewModel.visibleEvents(state, scope, topic)

    PccScreenBackground {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = 16.dp, end = 16.dp,
                top = contentPadding.calculateTopPadding() + 16.dp,
                bottom = contentPadding.calculateBottomPadding() + 24.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                Text("What's On", style = MaterialTheme.typography.headlineMedium)
                Text("Make a plan, discover something local, and never miss a good day out.", style = MaterialTheme.typography.bodyMedium)
            }
            item {
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    DateScope.entries.forEachIndexed { i, s ->
                        SegmentedButton(
                            selected = s == scope,
                            onClick = { viewModel.setDateScope(s) },
                            shape = SegmentedButtonDefaults.itemShape(i, DateScope.entries.size),
                        ) { Text(s.chipLabel, maxLines = 1) }
                    }
                }
            }
            item {
                Text("Browse by topic", style = MaterialTheme.typography.titleLarge)
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TopicChip("All", topic == null) { viewModel.setTopic(null) }
                    EventCategory.entries.forEach { c -> TopicChip(c.shortLabel, topic == c) { viewModel.setTopic(c) } }
                }
            }
            item {
                PccCard {
                    Text("Showing ${state.selectedScope.name}", style = MaterialTheme.typography.titleLarge)
                    Text("${state.selectedScope.kind.label} · ${visible.size} listing${if (visible.size == 1) "" else "s"}", style = MaterialTheme.typography.bodyMedium)
                    AreaButton(state.selectedScope) { showPicker = true }
                    ScopeChipRow(state.catalog.ancestorScopes(state.selectedId), green = true, onSelect = viewModel::selectScope)
                }
            }
            when {
                state.isLoading -> item { LoadingCard() }
                state.error != null -> item { FeedMessageCard("Events could not be loaded", state.error!!, viewModel::reload) }
                else -> {
                    item {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(WhatsOnViewModel.feedTitle(scope, topic), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f))
                            Spacer(Modifier)
                            Chip("${visible.size}", PccColors.PohutukawaOrange, Color.White)
                        }
                    }
                    if (visible.isEmpty()) {
                        item { FeedMessageCard(WhatsOnViewModel.emptyTitle(scope), WhatsOnViewModel.emptyMessage(scope, state.selectedScope.name)) }
                    } else {
                        items(visible, key = { it.id }) { EventCard(it) }
                    }
                }
            }
        }
    }

    if (showPicker) {
        LocationPickerSheet(
            catalog = state.catalog,
            selected = state.selectedScope,
            onSelect = { viewModel.selectScope(it); showPicker = false },
            onDismiss = { showPicker = false },
        )
    }
}

@Composable
private fun TopicChip(label: String, selected: Boolean, onClick: () -> Unit) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(label) },
        colors = FilterChipDefaults.filterChipColors(
            selectedContainerColor = PccColors.PohutukawaRed,
            selectedLabelColor = Color.White,
            labelColor = PccColors.Text,
        ),
    )
}
