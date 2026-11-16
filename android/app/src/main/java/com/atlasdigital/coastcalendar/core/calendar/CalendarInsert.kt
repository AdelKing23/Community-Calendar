package com.atlasdigital.coastcalendar.core.calendar

import android.content.Intent
import android.provider.CalendarContract
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import java.time.ZoneId
import java.time.ZoneOffset

/**
 * Values for the system "add event" screen (iOS `EventKit` save in EngagementActionRow → "Device calendar").
 * All-day listings: Android's calendar provider expects all-day spans as UTC midnights with an exclusive end,
 * so a one-day listing becomes [day 00:00Z, next day 00:00Z) and does not shift a day in NZ.
 */
data class CalendarInsert(
    val title: String,
    val beginMillis: Long,
    val endMillis: Long,
    val allDay: Boolean,
    val location: String,
    val description: String,
) {
    fun toIntent(): Intent = Intent(Intent.ACTION_INSERT, CalendarContract.Events.CONTENT_URI)
        .putExtra(CalendarContract.Events.TITLE, title)
        .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, beginMillis)
        .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endMillis)
        .putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, allDay)
        .putExtra(CalendarContract.Events.EVENT_LOCATION, location)
        .putExtra(CalendarContract.Events.DESCRIPTION, description)

    companion object {
        fun of(event: LocalEvent, zone: ZoneId = ZoneId.systemDefault()): CalendarInsert {
            val location = listOf(event.venue, event.displayLocationName).filter { it.isNotBlank() }.joinToString(", ")
            val description = event.shortDescription.ifBlank { event.publicLongDescription }
            return if (event.isAllDay) {
                val firstDay = event.start.atZone(zone).toLocalDate()
                val lastDay = maxOf(event.end, event.start).atZone(zone).toLocalDate()
                CalendarInsert(
                    title = event.title,
                    beginMillis = firstDay.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
                    endMillis = lastDay.plusDays(1).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
                    allDay = true,
                    location = location,
                    description = description,
                )
            } else {
                CalendarInsert(
                    title = event.title,
                    beginMillis = event.start.toEpochMilli(),
                    endMillis = maxOf(event.end, event.start).toEpochMilli(),
                    allDay = false,
                    location = location,
                    description = description,
                )
            }
        }
    }
}
