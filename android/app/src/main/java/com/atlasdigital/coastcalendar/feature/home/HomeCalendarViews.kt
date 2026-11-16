package com.atlasdigital.coastcalendar.feature.home

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.atlasdigital.coastcalendar.data.model.EventCategory
import com.atlasdigital.coastcalendar.ui.components.PccCard
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import com.atlasdigital.coastcalendar.ui.theme.PccTopicPalette
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.util.Locale

/** iOS `HomeViewModeToggle`: calendar icon on the board, stack icon on the calendar. */
@Composable
fun HomeViewModeToggle(mode: HomeViewMode, onToggle: () -> Unit) {
    Box(
        Modifier.size(40.dp).clip(CircleShape).background(PccColors.LeafGreen.copy(alpha = 0.10f)).clickable(onClick = onToggle)
            .semantics { contentDescription = if (mode == HomeViewMode.Board) "Show calendar" else "Show board" },
        contentAlignment = Alignment.Center,
    ) {
        Icon(if (mode == HomeViewMode.Board) Icons.Filled.DateRange else Icons.Filled.Menu, contentDescription = null, tint = PccColors.LeafGreen)
    }
}

/** iOS `HomeCalendarLegend`. */
@Composable
fun HomeCalendarLegend() {
    Row(
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier.horizontalScroll(rememberScrollState()).semantics { contentDescription = "Dot colours show listing topics" },
    ) {
        EventCategory.entries.forEach { c ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.86f)).padding(horizontal = 9.dp, vertical = 6.dp),
            ) {
                Box(Modifier.size(8.dp).clip(CircleShape).background(PccTopicPalette.color(c)))
                Spacer(Modifier.width(5.dp))
                Text(c.shortLabel, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = PccColors.Text)
            }
        }
    }
}

private val MONTH_TITLE = DateTimeFormatter.ofPattern("MMMM yyyy", Locale.getDefault())
private val WEEKDAYS = listOf("M", "T", "W", "T", "F", "S", "S")

/** iOS `HomeCalendarMonthCard`: Monday-first grid, today in orange, past days dimmed, up to 4 topic dots then "+". */
@Composable
fun HomeCalendarMonthCard(
    month: YearMonth,
    topicsByDay: Map<LocalDate, List<EventCategory>>,
    today: LocalDate,
    isLoading: Boolean,
    didFail: Boolean,
    onRetry: () -> Unit,
    onSelectDay: (LocalDate) -> Unit,
    allowPastDays: Boolean = false,
    selectedDay: LocalDate? = null,
) {
    PccCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(MONTH_TITLE.format(month), style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Black), color = PccColors.Ink)
            Spacer(Modifier.weight(1f))
            if (isLoading) {
                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = PccColors.PohutukawaOrange)
            } else if (didFail) {
                TextButton(onClick = onRetry) { Text("Try again", color = PccColors.PohutukawaOrange, fontWeight = FontWeight.Black) }
            }
        }
        Row(Modifier.fillMaxWidth()) {
            WEEKDAYS.forEach { label ->
                Text(label, fontSize = 11.sp, fontWeight = FontWeight.Black, color = PccColors.Text,
                    modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            }
        }
        HomeCalendarLogic.gridCells(month).chunked(7).forEach { week ->
            Row(Modifier.fillMaxWidth()) {
                week.forEach { day ->
                    Box(Modifier.weight(1f)) {
                        if (day != null) DayCell(day, today, topicsByDay[day].orEmpty(), onSelectDay, allowPastDays, day == selectedDay)
                    }
                }
                repeat(7 - week.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun DayCell(
    day: LocalDate, today: LocalDate, topics: List<EventCategory>, onSelect: (LocalDate) -> Unit,
    allowPast: Boolean = false, isSelected: Boolean = false,
) {
    val isPast = day < today && !allowPast
    val isToday = day == today
    val visible = topics.take(HomeCalendarLogic.MAXIMUM_VISIBLE_DOTS)
    val overflow = topics.size - visible.size
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp).alpha(if (isPast) 0.32f else 1f)
            .clickable(enabled = !isPast) { onSelect(day) }
            .semantics {
                val date = DateTimeFormatter.ofPattern("EEEE d MMMM").format(day)
                val prefix = if (isToday) "Today, $date" else date
                contentDescription = if (topics.isEmpty()) "$prefix, nothing listed" else "$prefix, ${topics.joinToString { it.shortLabel }}"
            },
    ) {
        Box(
            Modifier.size(30.dp).clip(CircleShape).background(
                when { isToday -> PccColors.PohutukawaOrange; isSelected -> PccColors.LeafGreen.copy(alpha = 0.18f); else -> Color.Transparent },
            ),
            contentAlignment = Alignment.Center,
        ) {
            Text("${day.dayOfMonth}", fontWeight = if (isToday) FontWeight.Black else FontWeight.Bold, color = if (isToday) Color.White else PccColors.Ink, fontSize = 14.sp)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically, modifier = Modifier.height(8.dp)) {
            visible.forEach { Box(Modifier.size(6.dp).clip(CircleShape).background(PccTopicPalette.color(it))) }
            if (overflow > 0) Text("+", fontSize = 9.sp, fontWeight = FontWeight.Black, color = PccColors.Text)
        }
    }
}
