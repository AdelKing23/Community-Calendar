package com.atlasdigital.coastcalendar.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import com.atlasdigital.coastcalendar.data.model.LocationCatalog
import com.atlasdigital.coastcalendar.data.model.LocationScope
import com.atlasdigital.coastcalendar.ui.theme.PccColors

/** iOS HomeHero area button: pin + selected area name + chevron. */
@Composable
fun AreaButton(scope: LocationScope, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .clip(CircleShape)
            .background(PccColors.LeafGreen.copy(alpha = 0.10f))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Filled.LocationOn, contentDescription = null, tint = PccColors.LeafGreen)
        Text(scope.name, style = MaterialTheme.typography.labelLarge, color = PccColors.LeafGreen, maxLines = 1)
        Icon(Icons.Filled.KeyboardArrowDown, contentDescription = "Change area", tint = PccColors.LeafGreen)
    }
}

/** Location pills, same pairing as iOS and web (t258): child / nearer areas solid orange #C2410C, parent / wider areas
 *  solid green #1F4D33, white text on both (5.18:1 and 9.69:1, WCAG AA). */
@Composable
fun ScopeChipRow(scopes: List<LocationScope>, green: Boolean, onSelect: (LocationScope) -> Unit) {
    if (scopes.isEmpty()) return
    Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        scopes.forEach { scope ->
            Text(
                scope.name,
                style = MaterialTheme.typography.labelMedium,
                color = Color.White,
                maxLines = 1,
                modifier = Modifier
                    .clip(CircleShape)
                    .background(if (green) PccColors.LeafGreen else PccColors.LocationChildPill)
                    .semantics { contentDescription = if (green) "${scope.name}, wider area" else "${scope.name}, nearby area" }
                    .clickable { onSelect(scope) }
                    .padding(horizontal = 12.dp, vertical = 8.dp),
            )
        }
    }
}

/** Simplified iOS `LocationFinderSheet`: "Use my location" (coarse, optional), current ladder + search the catalogue. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LocationPickerSheet(
    catalog: LocationCatalog,
    selected: LocationScope,
    onSelect: (LocationScope) -> Unit,
    onDismiss: () -> Unit,
) {
    var query by remember { mutableStateOf("") }
    val context = androidx.compose.ui.platform.LocalContext.current
    val container = LocalAppContainer.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var locating by remember { mutableStateOf(false) }
    var locationMessage by remember { mutableStateOf<String?>(null) }

    fun useLocation() {
        locating = true
        locationMessage = null
        scope.launch {
            val fix = com.atlasdigital.coastcalendar.core.location.CoarseLocation.current(context)
            if (fix == null) {
                locating = false
                locationMessage = "We couldn’t read your location. Choose an area to set where you belong."
                return@launch
            }
            val (id, remoteName) = container?.nearestScope?.resolve(fix.latitude, fix.longitude)
                ?: (com.atlasdigital.coastcalendar.core.location.KnownCoordinates.nearest(fix.latitude, fix.longitude) to null)
            val match = catalog.scope(id) ?: catalog.defaultScope(id)
            locating = false
            locationMessage = "We’ll start with ${remoteName ?: match.name}."
            onSelect(match)
        }
    }
    val permission = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission(),
    ) { granted ->
        if (granted) useLocation() else locationMessage = "No worries. Choose an area from the list to set where you belong."
    }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = PccColors.Cream) {
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Find events near...", style = MaterialTheme.typography.headlineSmall)
            Text("Choose a local area or search a wider region.", style = MaterialTheme.typography.bodyMedium)
            Row(
                Modifier.fillMaxWidth().clip(CircleShape).background(PccColors.LeafGreen.copy(alpha = 0.10f))
                    .clickable(enabled = !locating) {
                        if (com.atlasdigital.coastcalendar.core.location.CoarseLocation.hasPermission(context)) useLocation()
                        else permission.launch(android.Manifest.permission.ACCESS_COARSE_LOCATION)
                    }
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(Icons.Filled.LocationOn, contentDescription = null, tint = PccColors.LeafGreen)
                Text(if (locating) "Finding your area…" else "Use my location", style = MaterialTheme.typography.labelLarge, color = PccColors.LeafGreen)
            }
            locationMessage?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = PccColors.Text) }
            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                label = { Text("Search places") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            val results = if (query.isBlank()) catalog.ladder(selected.id) + catalog.primaryChips(selected.id) else catalog.search(query)
            LazyColumn(Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
                items(results.distinctBy { it.id }, key = { it.id }) { scope ->
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .clickable { onSelect(scope) }
                            .padding(vertical = 12.dp),
                    ) {
                        Text(scope.name, style = MaterialTheme.typography.titleMedium, color = if (scope.id == selected.id) PccColors.PohutukawaRed else PccColors.Ink)
                        Text("${scope.kind.label} · ${scope.subtitle}", style = MaterialTheme.typography.bodyMedium)
                    }
                    HorizontalDivider(color = PccColors.Ink.copy(alpha = 0.08f))
                }
            }
        }
    }
}
