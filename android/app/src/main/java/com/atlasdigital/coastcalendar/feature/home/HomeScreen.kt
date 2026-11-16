package com.atlasdigital.coastcalendar.feature.home

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.atlasdigital.coastcalendar.data.repository.UserSession
import com.atlasdigital.coastcalendar.ui.components.AreaButton
import com.atlasdigital.coastcalendar.ui.components.EventCard
import com.atlasdigital.coastcalendar.ui.components.FeedMessageCard
import com.atlasdigital.coastcalendar.ui.components.LoadingCard
import com.atlasdigital.coastcalendar.ui.components.LocationPickerSheet
import com.atlasdigital.coastcalendar.ui.components.PccCard
import com.atlasdigital.coastcalendar.ui.components.ScopeChipRow
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import com.atlasdigital.coastcalendar.ui.theme.PccScreenBackground
import com.atlasdigital.coastcalendar.ui.theme.PccShapes

/** iOS Home board: hero (greeting, brand, area, chips, counter) then the board feed or the empty/error card. */
@Composable
fun HomeScreen(viewModel: HomeViewModel, session: UserSession?, contentPadding: PaddingValues, onOpen: (String) -> Unit = {}) {
    val state by viewModel.state.collectAsState()
    var showPicker by remember { mutableStateOf(false) }
    val board = viewModel.boardEvents(state)

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
                PccCard {
                    PersonalGreeting.line(session?.greetingName)?.let { Text(it, style = MaterialTheme.typography.titleLarge.copy(color = PccColors.Text)) }
                    Column {
                        Text("Coast", fontFamily = FontFamily.Serif, fontWeight = FontWeight.Black, fontSize = 38.sp, color = PccColors.Ink)
                        Text("Calendar", fontFamily = FontFamily.Serif, fontWeight = FontWeight.Black, fontSize = 44.sp, color = PccColors.PohutukawaOrange)
                    }
                    AreaButton(state.selectedScope) { showPicker = true }
                    ScopeChipRow(state.catalog.primaryChips(state.selectedId), green = false, onSelect = viewModel::selectScope)
                    ScopeChipRow(state.catalog.ancestorScopes(state.selectedId), green = true, onSelect = viewModel::selectScope)
                    Text(
                        "Your local guide to markets, music, family days, fundraisers and everything happening around ${state.selectedScope.name}.",
                        style = MaterialTheme.typography.bodyLarge,
                    )
                    Row(
                        Modifier.clip(PccShapes.Small).background(PccColors.Cream).padding(horizontal = 12.dp, vertical = 10.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text("${board.size}", style = MaterialTheme.typography.titleLarge)
                        Text(if (board.size == 1) "listing" else "listings", style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(top = 4.dp))
                    }
                }
            }
            when {
                state.isLoading -> item { LoadingCard() }
                state.error != null -> item { FeedMessageCard("Local board could not be loaded", state.error!!, viewModel::reload) }
                board.isEmpty() -> item { FeedMessageCard("It’s a quiet time right now", "List something to be the first thing this week.") }
                else -> items(board, key = { it.id }) { event -> EventCard(event) { onOpen(event.id) } }
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

/** iOS `PCCPersonalGreeting`. */
object PersonalGreeting {
    fun line(name: String?, hour: Int = java.time.LocalTime.now().hour): String? {
        if (name.isNullOrBlank()) return null
        val hello = when (hour) {
            in 5..11 -> "Good morning"
            in 12..16 -> "Good afternoon"
            else -> "Good evening"
        }
        return "$hello $name"
    }
}
