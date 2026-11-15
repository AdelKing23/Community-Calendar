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
import androidx.compose.ui.unit.dp
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

/** iOS sibling chips (grey) and ancestor chips (green). */
@Composable
fun ScopeChipRow(scopes: List<LocationScope>, green: Boolean, onSelect: (LocationScope) -> Unit) {
    if (scopes.isEmpty()) return
    Row(modifier = Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        scopes.forEach { scope ->
            Text(
                scope.name,
                style = MaterialTheme.typography.labelMedium,
                color = if (green) PccColors.LeafGreen else PccColors.Text,
                maxLines = 1,
                modifier = Modifier
                    .clip(CircleShape)
                    .background(if (green) PccColors.LeafGreen.copy(alpha = 0.10f) else PccColors.Ink.copy(alpha = 0.06f))
                    .clickable { onSelect(scope) }
                    .padding(horizontal = 12.dp, vertical = 8.dp),
            )
        }
    }
}

/** Simplified iOS `LocationFinderSheet`: current ladder + search the catalogue. (No device location yet.) */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LocationPickerSheet(
    catalog: LocationCatalog,
    selected: LocationScope,
    onSelect: (LocationScope) -> Unit,
    onDismiss: () -> Unit,
) {
    var query by remember { mutableStateOf("") }
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = PccColors.Cream) {
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Find events near...", style = MaterialTheme.typography.headlineSmall)
            Text("Choose a local area or search a wider region.", style = MaterialTheme.typography.bodyMedium)
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
