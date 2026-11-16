package com.atlasdigital.coastcalendar.core.reminders

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.atlasdigital.coastcalendar.MainActivity
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.time.Duration
import java.time.Instant

/** iOS `EventReminderLeadTime` (same raw values, titles and offsets; default 1 hour). */
enum class ReminderLeadTime(val raw: String, val title: String, val offset: Duration) {
    AtStart("atStart", "At start time", Duration.ZERO),
    FiveMinutes("fiveMinutes", "5 minutes before", Duration.ofMinutes(5)),
    FifteenMinutes("fifteenMinutes", "15 minutes before", Duration.ofMinutes(15)),
    ThirtyMinutes("thirtyMinutes", "30 minutes before", Duration.ofMinutes(30)),
    OneHour("oneHour", "1 hour before", Duration.ofHours(1)),
    TwoHours("twoHours", "2 hours before", Duration.ofHours(2)),
    OneDay("oneDay", "1 day before", Duration.ofDays(1)),
    OneWeek("oneWeek", "1 week before", Duration.ofDays(7));

    companion object {
        val Default = OneHour
        fun from(raw: String?) = entries.firstOrNull { it.raw == raw }
    }
}

/** iOS `EventReminderStore` timing rules, kept pure for tests. */
object ReminderMath {
    /** Listings starting within a minute can't get a reminder. */
    fun canSchedule(start: Instant, now: Instant = Instant.now()): Boolean = start > now.plusSeconds(60)

    /** start − lead; if that is already (nearly) past, fire in a minute but never later than 30 s before start. */
    fun triggerAt(start: Instant, lead: ReminderLeadTime, now: Instant = Instant.now()): Instant {
        val preferred = start.minus(lead.offset)
        val minimum = now.plusSeconds(60)
        if (preferred > minimum) return preferred
        return minOf(minimum, start.minusSeconds(30))
    }
}

@Serializable
data class StoredReminder(val eventId: String, val title: String, val body: String, val triggerAtMillis: Long, val lead: String)

sealed interface ScheduleResult {
    data class Scheduled(val at: Instant) : ScheduleResult
    data object Denied : ScheduleResult
    data object Unavailable : ScheduleResult
}

/**
 * Local reminders on this device (no server writes), like iOS: per-listing reminder with a chosen lead time,
 * optional automatic reminder when you tap Going, and a default lead time in Settings.
 * Uses AlarmManager (inexact while idle unless exact alarms are already allowed; no exact-alarm permission requested).
 */
class EventReminderStore(context: Context) {
    private val app = context.applicationContext
    private val prefs = app.getSharedPreferences("coast_calendar_reminders", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }

    var automaticGoingReminders: Boolean
        get() = prefs.getBoolean(KEY_AUTO, true)
        set(value) {
            prefs.edit().putBoolean(KEY_AUTO, value).apply()
            if (!value) cancelAll()
        }

    var defaultLeadTime: ReminderLeadTime
        get() = ReminderLeadTime.from(prefs.getString(KEY_DEFAULT_LEAD, null)) ?: ReminderLeadTime.Default
        set(value) { prefs.edit().putString(KEY_DEFAULT_LEAD, value.raw).apply() }

    fun hasReminder(eventId: String): Boolean = stored().containsKey(eventId.uppercase())
    val activeCount: Int get() = stored().size

    fun leadTime(eventId: String): ReminderLeadTime =
        ReminderLeadTime.from(prefs.getString(KEY_LEAD_PREFIX + eventId.uppercase(), null)) ?: defaultLeadTime

    fun notificationsAllowed(): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(app, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return false
        return NotificationManagerCompat.from(app).areNotificationsEnabled()
    }

    /** Going toggled: schedule with the event's lead time when auto reminders are on, otherwise cancel. */
    fun syncGoing(event: LocalEvent, isGoing: Boolean) {
        if (isGoing && automaticGoingReminders && notificationsAllowed()) schedule(event, leadTime(event.id))
        else if (!isGoing) cancel(event.id)
    }

    fun schedule(event: LocalEvent, lead: ReminderLeadTime): ScheduleResult {
        val now = Instant.now()
        if (!ReminderMath.canSchedule(event.start, now)) { cancel(event.id); return ScheduleResult.Unavailable }
        prefs.edit().putString(KEY_LEAD_PREFIX + event.id.uppercase(), lead.raw).apply()
        if (!notificationsAllowed()) return ScheduleResult.Denied
        val at = ReminderMath.triggerAt(event.start, lead, now)
        val r = StoredReminder(
            eventId = event.id.uppercase(),
            title = event.title,
            body = "Starts ${event.timeText()} at ${event.venue}, ${event.displayLocationName}.",
            triggerAtMillis = at.toEpochMilli(),
            lead = lead.raw,
        )
        arm(r)
        save(stored() + (r.eventId to r))
        return ScheduleResult.Scheduled(at)
    }

    fun cancel(eventId: String) {
        val id = eventId.uppercase()
        alarmManager().cancel(pending(id, null))
        save(stored() - id)
    }

    fun cancelAll() = stored().keys.forEach(::cancel)

    /** After reboot or app update: re-arm future reminders, drop past ones. */
    fun rearmAll() {
        val now = System.currentTimeMillis()
        val keep = stored().filterValues { it.triggerAtMillis > now }
        keep.values.forEach(::arm)
        save(keep)
    }

    internal fun remove(eventId: String) = save(stored() - eventId.uppercase())

    private fun arm(r: StoredReminder) {
        val am = alarmManager()
        val pi = pending(r.eventId, r)
        if (Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, r.triggerAtMillis, pi)
        } else {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, r.triggerAtMillis, pi)
        }
    }

    private fun pending(eventId: String, r: StoredReminder?): PendingIntent {
        val intent = Intent(app, ReminderReceiver::class.java).setAction(ACTION_FIRE).putExtra(EXTRA_EVENT_ID, eventId)
        if (r != null) intent.putExtra(EXTRA_TITLE, r.title).putExtra(EXTRA_BODY, r.body)
        return PendingIntent.getBroadcast(app, eventId.hashCode(), intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun alarmManager() = app.getSystemService(AlarmManager::class.java)

    private fun stored(): Map<String, StoredReminder> =
        runCatching { json.decodeFromString<Map<String, StoredReminder>>(prefs.getString(KEY_STORED, "{}") ?: "{}") }.getOrDefault(emptyMap())

    private fun save(map: Map<String, StoredReminder>) { prefs.edit().putString(KEY_STORED, json.encodeToString(map)).apply() }

    companion object {
        const val CHANNEL_ID = "listing_reminders"
        const val ACTION_FIRE = "com.atlasdigital.coastcalendar.REMINDER"
        const val EXTRA_EVENT_ID = "event_id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        private const val KEY_STORED = "reminders"
        private const val KEY_AUTO = "automatic_going_reminders"
        private const val KEY_DEFAULT_LEAD = "reminder_lead_time"
        private const val KEY_LEAD_PREFIX = "lead_"

        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= 26) {
                val nm = context.getSystemService(NotificationManager::class.java)
                nm.createNotificationChannel(NotificationChannel(CHANNEL_ID, "Listing reminders", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "Reminders you set for listings on this device."
                })
            }
        }
    }
}

/** Posts the reminder notification; tapping opens the app on that listing. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val eventId = intent.getStringExtra(EventReminderStore.EXTRA_EVENT_ID) ?: return
        EventReminderStore(context).remove(eventId)
        if (Build.VERSION.SDK_INT >= 33 &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        EventReminderStore.ensureChannel(context)
        val open = PendingIntent.getActivity(
            context, eventId.hashCode(),
            Intent(context, MainActivity::class.java).putExtra(MainActivity.EXTRA_OPEN_EVENT_ID, eventId)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val n = NotificationCompat.Builder(context, EventReminderStore.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_my_calendar)
            .setContentTitle(intent.getStringExtra(EventReminderStore.EXTRA_TITLE) ?: "Coast Calendar reminder")
            .setContentText(intent.getStringExtra(EventReminderStore.EXTRA_BODY) ?: "")
            .setStyle(NotificationCompat.BigTextStyle().bigText(intent.getStringExtra(EventReminderStore.EXTRA_BODY) ?: ""))
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        runCatching { NotificationManagerCompat.from(context).notify(eventId.hashCode(), n) }
    }
}

/** Alarms don't survive a reboot; re-arm stored reminders. */
class ReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            EventReminderStore(context).rearmAll()
        }
    }
}
