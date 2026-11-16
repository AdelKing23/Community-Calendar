package com.atlasdigital.coastcalendar.feature.calendar

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimeInput
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.core.prefs.AppPreferences.Engagement
import com.atlasdigital.coastcalendar.data.remote.ErrorMessages
import com.atlasdigital.coastcalendar.data.repository.CalendarItem
import com.atlasdigital.coastcalendar.data.repository.UserSession
import com.atlasdigital.coastcalendar.feature.home.HomeCalendarLogic
import com.atlasdigital.coastcalendar.feature.home.HomeCalendarMonthCard
import com.atlasdigital.coastcalendar.feature.mylistings.PushedScaffold
import com.atlasdigital.coastcalendar.ui.components.Chip
import com.atlasdigital.coastcalendar.ui.components.PccCard
import com.atlasdigital.coastcalendar.ui.components.PrimaryButton
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.LocalTime
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

data class CalendarState(
    val items: List<CalendarItem> = emptyList(),
    val loading: Boolean = false,
    val error: String? = null,
    val month: YearMonth = YearMonth.now(ZoneId.systemDefault()),
    val selectedDay: LocalDate = LocalDate.now(ZoneId.systemDefault()),
    val canWrite: Boolean = false,
    val saving: Boolean = false,
    val saveError: String? = null,
)

/** Shared month grid + day list state (iOS `OrgMonthGrid`). */
abstract class CalendarViewModel(protected val container: AppContainer) : ViewModel() {
    protected val _state = MutableStateFlow(CalendarState())
    val state = _state.asStateFlow()
    val zone: ZoneId = ZoneId.systemDefault()
    protected var session: UserSession? = null

    protected abstract suspend fun fetch(): List<CalendarItem>
    protected open suspend fun resolveCanWrite(): Boolean = false

    fun bind(s: UserSession?) {
        session = s
        load()
    }

    fun load() {
        _state.update { it.copy(loading = true, error = null) }
        viewModelScope.launch {
            try {
                val items = fetch()
                container.eventCache.put(items.map { it.event })
                val canWrite = runCatching { resolveCanWrite() }.getOrDefault(false)
                _state.update { it.copy(items = items, loading = false, canWrite = canWrite) }
            } catch (e: Exception) {
                _state.update { it.copy(loading = false, error = ErrorMessages.userFacing(e)) }
            }
        }
    }

    fun shiftMonth(delta: Long) = _state.update { it.copy(month = it.month.plusMonths(delta)) }
    fun today() = _state.update { it.copy(month = YearMonth.now(zone), selectedDay = LocalDate.now(zone)) }
    fun select(day: LocalDate) = _state.update { it.copy(selectedDay = day) }

    fun dayItems(s: CalendarState = _state.value): List<CalendarItem> {
        val ids = HomeCalendarLogic.dayEvents(s.items.map { it.event }, s.selectedDay, zone).map { it.id }.toSet()
        return s.items.filter { it.event.id in ids }
    }
}

/** iOS `MyCalendarSheet`: org-calendar notes from organisations you Belong to (or own) + listings you're Going to. */
class MyCalendarViewModel(container: AppContainer) : CalendarViewModel(container) {
    override suspend fun fetch(): List<CalendarItem> {
        if (session == null) return emptyList()
        return container.calendar.myCalendar(container.prefs.engagementIds(Engagement.Going))
    }
}

/** iOS `OrgCalendarSheet`: an organisation's calendar notes + its published listings; the owner can add a date. */
class OrgCalendarViewModel(container: AppContainer, private val profileId: String) : CalendarViewModel(container) {
    override suspend fun fetch(): List<CalendarItem> = container.calendar.orgCalendar(profileId)

    override suspend fun resolveCanWrite(): Boolean {
        val s = session ?: return false
        return container.account.businessAccount(s.userId).profile?.id.equals(profileId, ignoreCase = true)
    }

    fun create(title: String, venue: String, details: String, time: LocalTime, isPublic: Boolean, onDone: () -> Unit) {
        if (title.trim().length < 2) { _state.update { it.copy(saveError = "Add a title of at least 2 characters.") }; return }
        if (session == null || !_state.value.canWrite) { _state.update { it.copy(saveError = "Sign in as the organisation owner to save.") }; return }
        val start = _state.value.selectedDay.atTime(time).atZone(zone).toInstant()
        _state.update { it.copy(saving = true, saveError = null) }
        viewModelScope.launch {
            try {
                container.calendar.insertOrgCalendarListing(profileId, title, venue, details, start, isPublic)
                _state.update { it.copy(saving = false) }
                onDone()
                load()
            } catch (e: Exception) {
                _state.update { it.copy(saving = false, saveError = ErrorMessages.userFacing(e)) }
            }
        }
    }

    fun clearSaveError() = _state.update { it.copy(saveError = null) }
}

private val DAY_TITLE = DateTimeFormatter.ofPattern("EEEE d MMMM", Locale("en", "NZ"))
private val TIME = DateTimeFormatter.ofPattern("h:mm a", Locale("en", "NZ"))

@Composable
fun MyCalendarScreen(viewModel: MyCalendarViewModel, session: UserSession?, onBack: () -> Unit, onSignIn: () -> Unit, onOpen: (String) -> Unit) {
    LaunchedEffect(session?.userId) { viewModel.bind(session) }
    PushedScaffold("My Calendar", onBack) { padding ->
        if (session == null) {
            Column(Modifier.padding(padding).padding(16.dp)) {
                PccCard {
                    Text("Sign in to see My Calendar", style = MaterialTheme.typography.titleMedium)
                    Text("My Calendar shows dates from organisations you Belong to and listings you're Going to.")
                    PrimaryButton("Sign in", onSignIn)
                }
            }
        } else {
            CalendarBody(viewModel, padding, "Nothing on this day from organisations you belong to.", null, onOpen)
        }
    }
}

@Composable
fun OrgCalendarScreen(viewModel: OrgCalendarViewModel, session: UserSession?, organiserName: String, onBack: () -> Unit, onOpen: (String) -> Unit) {
    LaunchedEffect(session?.userId) { viewModel.bind(session) }
    val state by viewModel.state.collectAsState()
    var creating by remember { mutableStateOf(false) }
    PushedScaffold("$organiserName calendar", onBack) { padding ->
        CalendarBody(
            viewModel, padding, "Nothing on this day yet.",
            footer = {
                if (state.canWrite) {
                    PrimaryButton("Create on this day", { viewModel.clearSaveError(); creating = true })
                } else {
                    Text("This calendar is filled by $organiserName. Belong to see private dates when they exist.", style = MaterialTheme.typography.bodySmall)
                }
            },
            onOpen = onOpen,
        )
    }
    if (creating) CreateOnThisDayDialog(viewModel) { creating = false }
}

@Composable
private fun CalendarBody(
    viewModel: CalendarViewModel,
    padding: androidx.compose.foundation.layout.PaddingValues,
    emptyText: String,
    footer: (@Composable () -> Unit)?,
    onOpen: (String) -> Unit,
) {
    val state by viewModel.state.collectAsState()
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(padding).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { viewModel.shiftMonth(-1) }) { Text("‹ Previous", color = PccColors.LeafGreen, fontWeight = FontWeight.Black) }
            Spacer(Modifier.weight(1f))
            TextButton(onClick = viewModel::today) { Text("Today", color = PccColors.PohutukawaOrange, fontWeight = FontWeight.Black) }
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { viewModel.shiftMonth(1) }) { Text("Next ›", color = PccColors.LeafGreen, fontWeight = FontWeight.Black) }
        }
        val today = LocalDate.now(viewModel.zone)
        HomeCalendarMonthCard(
            month = state.month,
            topicsByDay = HomeCalendarLogic.topicsByDay(state.items.map { it.event }, state.month, viewModel.zone),
            today = today,
            isLoading = state.loading,
            didFail = state.error != null,
            onRetry = viewModel::load,
            onSelectDay = viewModel::select,
            allowPastDays = true,
            selectedDay = state.selectedDay,
        )
        Text(DAY_TITLE.format(state.selectedDay), style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black), color = PccColors.Ink)
        val day = viewModel.dayItems(state)
        if (day.isEmpty()) {
            Text(emptyText, style = MaterialTheme.typography.bodyMedium)
        } else {
            day.forEach { item -> NoteCard(item, viewModel.zone) { onOpen(item.event.id) } }
        }
        footer?.invoke()
    }
}

/** iOS `OrgCalendarNoteCard`. */
@Composable
private fun NoteCard(item: CalendarItem, zone: ZoneId, onOpen: () -> Unit) {
    val e = item.event
    PccCard(onClick = onOpen) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            Chip(if (item.isNote) "Calendar" else e.category.shortLabel, if (item.isNote) PccColors.LeafGreen else PccColors.PohutukawaOrange, Color.White)
            if (item.isPrivate) Chip("Belong only", PccColors.Ink.copy(alpha = 0.78f), Color.White)
        }
        Text(e.title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black), color = PccColors.Ink)
        Text(
            listOfNotNull(TIME.format(e.start.atZone(zone)), e.venue.ifBlank { null }, e.organiserDisplayName).joinToString(" · "),
            style = MaterialTheme.typography.labelMedium,
        )
        if (e.shortDescription.isNotBlank()) Text(e.shortDescription, maxLines = 3)
    }
}

/** iOS `OrgCreateOnThisDaySheet`: title, venue, time, details, Public listing toggle. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CreateOnThisDayDialog(viewModel: OrgCalendarViewModel, onDismiss: () -> Unit) {
    val state by viewModel.state.collectAsState()
    var title by remember { mutableStateOf("") }
    var venue by remember { mutableStateOf("") }
    var details by remember { mutableStateOf("") }
    var isPublic by remember { mutableStateOf(true) }
    val time = rememberTimePickerState(initialHour = 12, initialMinute = 0, is24Hour = false)
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Create on this day") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(DAY_TITLE.format(state.selectedDay), fontWeight = FontWeight.Bold)
                OutlinedTextField(title, { title = it }, label = { Text("Title") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(venue, { venue = it }, label = { Text("Venue") }, placeholder = { Text("Beachlands Boat Club") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                Text("Time", fontWeight = FontWeight.Bold)
                TimeInput(state = time)
                OutlinedTextField(details, { details = it }, label = { Text("Details") }, placeholder = { Text("Julie is bringing lunch") }, minLines = 2, modifier = Modifier.fillMaxWidth())
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Public listing", fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    Switch(checked = isPublic, onCheckedChange = { isPublic = it })
                }
                if (!isPublic) Text("People who Belong to this organisation can see this date. It is not on the public board.", style = MaterialTheme.typography.bodySmall)
                state.saveError?.let { Text(it, color = PccColors.PohutukawaRed) }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { viewModel.create(title, venue, details, LocalTime.of(time.hour, time.minute), isPublic, onDismiss) },
                enabled = !state.saving,
            ) { Text(if (state.saving) "Saving" else "Save", fontWeight = FontWeight.Black, color = PccColors.LeafGreen) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Close") } },
    )
}
