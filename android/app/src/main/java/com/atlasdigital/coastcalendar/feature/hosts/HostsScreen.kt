package com.atlasdigital.coastcalendar.feature.hosts

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.atlasdigital.coastcalendar.data.model.HostDirectoryItem
import com.atlasdigital.coastcalendar.ui.components.AreaButton
import com.atlasdigital.coastcalendar.ui.components.FeedMessageCard
import com.atlasdigital.coastcalendar.ui.components.LoadingCard
import com.atlasdigital.coastcalendar.ui.components.LocationPickerSheet
import com.atlasdigital.coastcalendar.ui.components.PccCard
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import com.atlasdigital.coastcalendar.ui.theme.PccScreenBackground

/** iOS `HostsScreen`: hero (Hosts · Organisations, count, area), "Local hosts", directory cards → Organisation page. */
@Composable
fun HostsScreen(viewModel: HostsViewModel, contentPadding: PaddingValues, onOpenHost: (String) -> Unit) {
    val state by viewModel.state.collectAsState()
    val profiles by viewModel.profiles.collectAsState()
    var showPicker by remember { mutableStateOf(false) }
    val hosts = viewModel.visibleHosts(state, profiles)
    val scope = state.selectedScope

    PccScreenBackground {
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(16.dp, contentPadding.calculateTopPadding() + 16.dp, 16.dp, contentPadding.calculateBottomPadding() + 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item {
                PccCard {
                    Text("Hosts", style = MaterialTheme.typography.headlineMedium)
                    Text("Organisations", style = MaterialTheme.typography.titleLarge, color = PccColors.PohutukawaOrange)
                    Text("Find schools, clubs, venues and groups around ${scope.name}.")
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("${hosts.size} ${if (hosts.size == 1) "host" else "hosts"}", fontWeight = FontWeight.Bold, color = PccColors.Ink)
                        AreaButton(scope) { showPicker = true }
                    }
                }
            }
            item {
                Text("Local hosts", style = MaterialTheme.typography.titleLarge)
                Text("Find schools, venues, clubs, groups and organisations publishing around ${scope.name}.", style = MaterialTheme.typography.bodyMedium)
            }
            when {
                state.isLoading -> item { LoadingCard("Loading hosts") }
                state.error != null && profiles.isEmpty() -> item { FeedMessageCard("Hosts could not be loaded", state.error ?: "", viewModel::refresh) }
                hosts.isEmpty() -> item {
                    FeedMessageCard("Hosts will appear here", "As organisations publish listings around ${scope.name}, their public pages will collect here.")
                }
                else -> items(hosts, key = { it.profile.id }) { host -> HostCard(host) { onOpenHost(host.profile.id) } }
            }
        }
    }
    if (showPicker) {
        LocationPickerSheet(state.catalog, scope, onSelect = { viewModel.selectScope(it); showPicker = false }) { showPicker = false }
    }
}

@Composable
private fun HostCard(host: HostDirectoryItem, onOpen: () -> Unit) {
    PccCard(onClick = onOpen) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(48.dp).clip(CircleShape).background(PccColors.LeafGreen), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Person, contentDescription = null, tint = Color.White)
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(host.name, fontWeight = FontWeight.Black, color = PccColors.Ink, maxLines = 2)
                Text(host.subtitle, style = MaterialTheme.typography.bodyMedium, maxLines = 2)
                Text(
                    "${host.events.size} upcoming" + if (host.pollCount > 0) " · ${host.pollCount} polls" else "",
                    style = MaterialTheme.typography.labelMedium, color = PccColors.LeafGreen,
                )
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = PccColors.PohutukawaOrange)
        }
    }
}
