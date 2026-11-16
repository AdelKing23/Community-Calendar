package com.atlasdigital.coastcalendar

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.mutableStateOf
import com.atlasdigital.coastcalendar.ui.navigation.CoastCalendarRoot
import com.atlasdigital.coastcalendar.ui.theme.CoastCalendarTheme
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import androidx.compose.ui.graphics.toArgb

class MainActivity : ComponentActivity() {
    /** Listing to open when the app is launched from a reminder notification. */
    private val openEventId = mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Light only, like iOS: dark system icons on the cream background.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.light(PccColors.Cream.toArgb(), PccColors.Cream.toArgb()),
            navigationBarStyle = SystemBarStyle.light(PccColors.Cream.toArgb(), PccColors.Cream.toArgb()),
        )
        val container = (application as CoastCalendarApp).container
        com.atlasdigital.coastcalendar.core.reminders.EventReminderStore.ensureChannel(this)
        if (savedInstanceState == null) openEventId.value = intent?.getStringExtra(EXTRA_OPEN_EVENT_ID)
        setContent {
            CoastCalendarTheme {
                CoastCalendarRoot(container, openEventId = openEventId.value, onOpenedEvent = { openEventId.value = null })
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra(EXTRA_OPEN_EVENT_ID)?.let { openEventId.value = it }
    }

    companion object {
        const val EXTRA_OPEN_EVENT_ID = "open_event_id"
    }
}
