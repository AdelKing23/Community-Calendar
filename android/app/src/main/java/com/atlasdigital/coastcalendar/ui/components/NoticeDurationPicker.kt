package com.atlasdigital.coastcalendar.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.atlasdigital.coastcalendar.data.model.NoticeExpiry
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private val endsFormat = DateTimeFormatter.ofPattern("EEE d MMM", Locale("en", "NZ"))

/** Notice expiry: 14 days by default, up to 90. Writes `member_notices.ends_at`. */
@Composable
fun NoticeDurationPicker(days: Int, onChange: (Int) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("Show this Notice for", style = MaterialTheme.typography.labelLarge, color = PccColors.Ink, fontWeight = FontWeight.Black)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(7, 14, 30, 90).forEach { d ->
                FilterChip(selected = days == d, onClick = { onChange(d) }, label = { Text("$d days") })
            }
        }
        Slider(
            value = days.toFloat(),
            onValueChange = { onChange(NoticeExpiry.clampDays(it.toInt())) },
            valueRange = NoticeExpiry.MIN_DAYS.toFloat()..NoticeExpiry.MAX_DAYS.toFloat(),
        )
        val ends = NoticeExpiry.endsAt(days).atZone(ZoneId.of("Pacific/Auckland"))
        Text(
            "$days day${if (days == 1) "" else "s"} · shows until ${endsFormat.format(ends)}. 14 days is the default, 90 days the most.",
            style = MaterialTheme.typography.bodySmall,
        )
    }
}
