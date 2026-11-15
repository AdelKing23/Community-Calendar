package com.atlasdigital.coastcalendar.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.atlasdigital.coastcalendar.BuildConfig
import com.atlasdigital.coastcalendar.data.repository.UserSession
import com.atlasdigital.coastcalendar.ui.components.PccCard
import com.atlasdigital.coastcalendar.ui.components.PrimaryButton
import com.atlasdigital.coastcalendar.ui.theme.PccScreenBackground

/**
 * Settings STUB (t237). Account basics only. Not yet ported from iOS: Organisation application/profile,
 * My Listings, notifications, wallpaper/card tint, Support inbox, deletion request, legal pages.
 * No plan purchase or payment wording until Google Play Billing is integrated.
 */
@Composable
fun SettingsScreen(session: UserSession?, contentPadding: PaddingValues, onSignIn: () -> Unit, onSignOut: () -> Unit, onShowWelcome: () -> Unit) {
    PccScreenBackground {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, end = 16.dp, top = contentPadding.calculateTopPadding() + 16.dp, bottom = contentPadding.calculateBottomPadding() + 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Settings", style = MaterialTheme.typography.headlineMedium)
            PccCard {
                Text("Account", style = MaterialTheme.typography.titleLarge)
                if (session == null) {
                    Text("Sign in to save listings, belong to organisations and manage your Organisation.", style = MaterialTheme.typography.bodyMedium)
                    PrimaryButton("Sign in or create account", onSignIn)
                } else {
                    session.fullName?.let { Text(it, style = MaterialTheme.typography.titleMedium) }
                    Text(session.email, style = MaterialTheme.typography.bodyMedium)
                    Text(if (session.isEmailVerified) "Email verified" else "Email not verified yet", style = MaterialTheme.typography.bodyMedium)
                    OutlinedButton(onClick = onSignOut, modifier = Modifier.fillMaxWidth()) { Text("Sign out") }
                }
            }
            PccCard {
                Text("Coming to Android next", style = MaterialTheme.typography.titleLarge)
                Text(
                    "Organisation application and profile, My Listings, notifications, appearance, Support messages and account deletion requests.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            PccCard {
                Text("About", style = MaterialTheme.typography.titleLarge)
                Text("Coast Calendar ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}) · Android preview", style = MaterialTheme.typography.bodyMedium)
                Text("Support: support@coastcalendar.nz", style = MaterialTheme.typography.bodyMedium)
                OutlinedButton(onClick = onShowWelcome, modifier = Modifier.fillMaxWidth()) { Text("Show welcome") }
            }
        }
    }
}
