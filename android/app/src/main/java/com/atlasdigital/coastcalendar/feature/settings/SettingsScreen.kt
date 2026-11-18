package com.atlasdigital.coastcalendar.feature.settings

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.atlasdigital.coastcalendar.BuildConfig
import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.data.model.BusinessAccountState
import com.atlasdigital.coastcalendar.data.repository.UserSession
import com.atlasdigital.coastcalendar.ui.components.PccCard
import com.atlasdigital.coastcalendar.ui.components.PrimaryButton
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import com.atlasdigital.coastcalendar.ui.theme.PccScreenBackground
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Loads the signed-in account's Organisation + Support flags for the Settings hub. */
class SettingsViewModel(private val container: AppContainer) : ViewModel() {
    val reminders get() = container.reminders
    private val _account = MutableStateFlow(BusinessAccountState.Empty)
    val account: StateFlow<BusinessAccountState> = _account.asStateFlow()

    fun load(session: UserSession?) {
        if (session == null) { _account.value = BusinessAccountState.Empty; return }
        viewModelScope.launch {
            _account.value = runCatching { container.account.businessAccount(session.userId) }.getOrDefault(BusinessAccountState.Empty)
        }
    }
}

/** Where Settings rows go (routes live in CoastCalendarRoot). */
data class SettingsNav(
    val onSignIn: () -> Unit,
    val onSignOut: () -> Unit,
    val onShowWelcome: () -> Unit,
    val onMyListings: () -> Unit,
    val onOrganisation: () -> Unit,
    val onContactSupport: () -> Unit,
    val onSupportDashboard: () -> Unit,
    val onDeleteAccount: () -> Unit,
    val onMyCalendar: () -> Unit,
)

/**
 * iOS Settings hub, Android subset: Organisations (Organisation, My listings), Support (dashboard for Support
 * accounts), Contact Support, Documents (Terms, Privacy on coastcalendar.nz), Account and About.
 * Not ported: engagements list, wallpaper/card colour.
 */
@Composable
fun SettingsScreen(viewModel: SettingsViewModel, session: UserSession?, contentPadding: PaddingValues, nav: SettingsNav) {
    val account by viewModel.account.collectAsState()
    val context = LocalContext.current
    LaunchedEffect(session?.userId) { viewModel.load(session) }
    fun openUrl(url: String) {
        try { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) } catch (_: ActivityNotFoundException) { }
    }

    PccScreenBackground {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, end = 16.dp, top = contentPadding.calculateTopPadding() + 16.dp, bottom = contentPadding.calculateBottomPadding() + 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Settings", style = MaterialTheme.typography.headlineMedium)

            Section("Organisations") {
                val status = account.profile?.let { p ->
                    when {
                        p.isApproved && account.canSubmitAsOrganisation -> "${p.businessName} · Approved"
                        p.isApproved -> "${p.businessName} · Approved, member access not active yet"
                        else -> "${p.businessName} · ${p.memberStatus.raw.replace('_', ' ').replaceFirstChar { it.uppercase() }}"
                    }
                } ?: "Organisations list on Coast Calendar. Register, then Support reviews your application."
                Row(Icons.Filled.Home, "Organisation", status, nav.onOrganisation)
                Row(Icons.AutoMirrored.Filled.List, "My listings", "Review, edit, remove, and follow Support feedback.", nav.onMyListings)
            }

            if (account.isSupport) {
                Section("Support") {
                    Row(Icons.Filled.Build, "Support dashboard", "Inbox, reports, applications, listings and change requests.", nav.onSupportDashboard)
                }
            }

            Section("My Calendar") {
                Row(Icons.Filled.DateRange, "My Calendar", "Dates from organisations you Belong to and listings you're Going to.", nav.onMyCalendar)
            }

            Section("Reminders") {
                var showReminders by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
                val store = viewModel.reminders
                Row(
                    Icons.Filled.Notifications, "Reminder settings",
                    "Choose how Going reminders behave on this device. " +
                        (if (store.automaticGoingReminders) store.defaultLeadTime.title else "Off") + " · ${store.activeCount} set",
                ) { showReminders = true }
                if (showReminders) ReminderSettingsDialog(store) { showReminders = false }
            }

            Section("Contact Support") {
                Row(Icons.Filled.Email, "Contact Coast Calendar", "Send a private support request from this app.", nav.onContactSupport)
            }

            Section("Privacy, terms and policies") {
                Row(Icons.Filled.Info, "Terms of Use", "Rules for using the Coast Calendar app and website.") { openUrl("https://coastcalendar.nz/terms") }
                Row(Icons.Filled.Lock, "Privacy Policy", "How Coast Calendar handles personal information.") { openUrl("https://coastcalendar.nz/privacy") }
            }

            Section("Account") {
                if (session == null) {
                    Text("Create a free account to save listings, set reminders, and Belong to organisations.", style = MaterialTheme.typography.bodyMedium)
                    PrimaryButton("Create account or sign in", nav.onSignIn)
                } else {
                    Row(Icons.Filled.AccountCircle, session.fullName ?: "Account", session.email + if (session.isEmailVerified) " · Email verified" else " · Email not verified", null)
                    OutlinedButton(onClick = nav.onSignOut, modifier = Modifier.fillMaxWidth()) { Text("Sign out") }
                    Row(Icons.Filled.Delete, "Request account deletion", "Ask Support to delete this account and its personal details.", nav.onDeleteAccount)
                }
            }

            Section("About") {
                Text("Coast Calendar ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}) · Android preview", style = MaterialTheme.typography.bodyMedium)
                OutlinedButton(onClick = nav.onShowWelcome, modifier = Modifier.fillMaxWidth()) { Text("Show welcome") }
            }
        }
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    PccCard {
        Text(title, style = MaterialTheme.typography.titleLarge)
        content()
    }
}

@Composable
private fun Row(icon: ImageVector, title: String, subtitle: String, onClick: (() -> Unit)?) {
    androidx.compose.foundation.layout.Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().let { if (onClick != null) it.clickable(onClick = onClick) else it }.padding(vertical = 6.dp),
    ) {
        Icon(icon, contentDescription = null, tint = PccColors.PohutukawaOrange, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.Bold, color = PccColors.Ink)
            Text(subtitle, style = MaterialTheme.typography.bodyMedium)
        }
        if (onClick != null) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = PccColors.Text)
    }
}


/** iOS `ReminderSettingsScreen`: Going reminders on/off and the default lead time (device only). */
@Composable
private fun ReminderSettingsDialog(store: com.atlasdigital.coastcalendar.core.reminders.EventReminderStore, onDismiss: () -> Unit) {
    var auto by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(store.automaticGoingReminders) }
    var lead by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(store.defaultLeadTime) }
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Reminders") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("When you tap Going, the app can remind you before the listing starts. Simple, local, and controlled on this device.")
                androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Going reminders", fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    androidx.compose.material3.Switch(checked = auto, onCheckedChange = { auto = it; store.automaticGoingReminders = it })
                }
                com.atlasdigital.coastcalendar.core.reminders.ReminderLeadTime.entries.forEach { option ->
                    androidx.compose.foundation.layout.Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth().clickable(enabled = auto) { lead = option; store.defaultLeadTime = option },
                    ) {
                        androidx.compose.material3.RadioButton(selected = lead == option, onClick = { lead = option; store.defaultLeadTime = option }, enabled = auto)
                        Text(option.title)
                    }
                }
            }
        },
        confirmButton = { androidx.compose.material3.TextButton(onClick = onDismiss) { Text("Done") } },
    )
}
