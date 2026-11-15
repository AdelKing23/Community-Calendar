package com.atlasdigital.coastcalendar.feature.hosts

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.atlasdigital.coastcalendar.ui.components.PccCard
import com.atlasdigital.coastcalendar.ui.theme.PccScreenBackground

/** Hosts STUB (t237). iOS Hosts = `public_host_directory`, host pages, Belong (`member_follows`) and notices. */
@Composable
fun HostsScreen(contentPadding: PaddingValues) {
    PccScreenBackground {
        Column(
            Modifier.fillMaxSize().padding(start = 16.dp, end = 16.dp, top = contentPadding.calculateTopPadding() + 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text("Hosts", style = MaterialTheme.typography.headlineMedium)
            PccCard {
                Text("Organisations near you", style = MaterialTheme.typography.titleLarge)
                Text("The host directory, Belong and notice boards are coming to Android next.", style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}
