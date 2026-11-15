package com.atlasdigital.coastcalendar.feature.welcome

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.atlasdigital.coastcalendar.ui.components.PrimaryButton
import com.atlasdigital.coastcalendar.ui.theme.PccColors

/** Same copy as iOS `WelcomeCopy` and web WELCOME_COPY. */
object WelcomeCopy {
    const val VERSION = 1
    const val TITLE = "Welcome to Coast Calendar"
    const val BODY = "Kia ora, and welcome. Coast Calendar is where locals share what’s on nearby: events, polls and notices from community groups and local organisations."
    val TIPS = listOf(
        "Browse Home, or switch to the calendar view to see what’s on each day.",
        "Choose your area to see what’s close to you.",
        "Save listings to My Calendar so you don’t miss them.",
        "Organisations can create an account and apply in Settings to start listing.",
        "Questions or feedback? Send us a Support message any time.",
    )
    const val SIGN_OFF = "Ngā mihi nui."
    const val BUTTON = "Get started"
}

/** iOS `WelcomeGate` (t224): signed in = server row decides, a server error shows it unless this device recorded the dismissal. */
object WelcomeGate {
    enum class ServerCheck { Dismissed, NotDismissed, Failed }

    fun shouldShow(signedIn: Boolean, server: ServerCheck, dismissedOnThisDevice: Boolean, signedOutDismissed: Boolean): Boolean {
        if (!signedIn) return !signedOutDismissed
        return when (server) {
            ServerCheck.Dismissed -> false
            ServerCheck.NotDismissed, ServerCheck.Failed -> !dismissedOnThisDevice
        }
    }

    fun accounts(raw: String): Set<String> = raw.split(",").filter { it.isNotEmpty() }.toSet()

    fun adding(userId: String, raw: String): String = (accounts(raw) + userId.lowercase()).sorted().joinToString(",")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WelcomeSheet(onDismiss: () -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = PccColors.Cream,
    ) {
        Column(
            Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 28.dp, vertical = 8.dp),
        ) {
            Box(
                Modifier.size(56.dp).clip(RoundedCornerShape(16.dp)).background(PccColors.PohutukawaRed),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Filled.DateRange, contentDescription = null, tint = Color.White) }
            Spacer(Modifier.height(24.dp))
            Text(WelcomeCopy.TITLE, style = MaterialTheme.typography.headlineMedium.copy(fontSize = 32.sp, fontWeight = FontWeight.Bold))
            Spacer(Modifier.height(16.dp))
            Text(WelcomeCopy.BODY, style = MaterialTheme.typography.bodyLarge)
            Spacer(Modifier.height(24.dp))
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Color.White.copy(alpha = 0.85f)).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                WelcomeCopy.TIPS.forEach { tip ->
                    Row(verticalAlignment = Alignment.Top) {
                        Icon(Icons.Filled.Check, contentDescription = null, tint = PccColors.LeafGreen, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.size(10.dp))
                        Text(tip, style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
            Text(WelcomeCopy.SIGN_OFF, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Bold))
            Spacer(Modifier.height(24.dp))
            PrimaryButton(WelcomeCopy.BUTTON, onClick = onDismiss)
            Spacer(Modifier.height(24.dp))
        }
    }
}
