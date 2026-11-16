package com.atlasdigital.coastcalendar.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.atlasdigital.coastcalendar.data.model.LocalEvent
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import com.atlasdigital.coastcalendar.ui.theme.PccShapes

/** iOS `.pccCardStyle()`: white card, 24 pt radius. */
@Composable
fun PccCard(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(PccShapes.Card)
            .background(PccColors.CardFill)
            .let { if (onClick != null) it.clickable(onClick = onClick) else it }
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        content = content,
    )
}

@Composable
fun Chip(text: String, background: Color, foreground: Color, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelMedium,
        color = foreground,
        maxLines = 1,
        modifier = modifier.clip(CircleShape).background(background).padding(horizontal = 10.dp, vertical = 6.dp),
    )
}

/** iOS `HomePostCard` (no image yet: Coast Calendar placeholder like `EventImagePlaceholderView`). */
@Composable
fun EventCard(event: LocalEvent, onOpen: () -> Unit = {}) {
    PccCard(onClick = onOpen) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (event.isPoll) Chip("Poll", PccColors.LeafGreen, Color.White)
            Chip(event.category.shortLabel, PccColors.PohutukawaOrange, Color.White)
            Text(
                event.displayLocationName,
                style = MaterialTheme.typography.labelMedium,
                color = PccColors.LeafGreen,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            if (event.isPromoted || event.isFeatured) {
                Icon(Icons.Filled.Star, contentDescription = null, tint = PccColors.PohutukawaOrange, modifier = Modifier.size(16.dp))
                Text(
                    if (event.isPromoted) event.promotionBadgeTitle else "Featured",
                    style = MaterialTheme.typography.labelMedium,
                    color = PccColors.PohutukawaOrange,
                )
            }
        }
        androidx.compose.foundation.layout.Box {
            com.atlasdigital.coastcalendar.feature.detail.ListingRemoteImage(
                event.primaryImage, isPoll = event.isPoll,
                modifier = Modifier.height(138.dp),
                contentScale = androidx.compose.ui.layout.ContentScale.Crop,
            )
            if (event.isFinished()) {
                Chip("Finished", PccColors.Ink.copy(alpha = 0.78f), Color.White, Modifier.align(Alignment.TopStart).padding(10.dp))
            }
        }
        Text(event.organiserDisplayName, style = MaterialTheme.typography.headlineSmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(event.title, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
        if (event.shortDescription.isNotBlank()) {
            Text(event.shortDescription, style = MaterialTheme.typography.bodyMedium, maxLines = 3, overflow = TextOverflow.Ellipsis)
        }
        MetaLine(Icons.Filled.DateRange, event.dateText())
        MetaLine(Icons.Filled.Refresh, event.timeText(), contentDescription = "Time")
        MetaLine(Icons.Filled.LocationOn, "${event.venue}, ${event.displayLocationName}")
        event.pollDetails?.let { poll ->
            Text(poll.question, style = MaterialTheme.typography.titleMedium, color = PccColors.Ink)
            poll.options.forEach { option ->
                Text("•  $option", style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

@Composable
private fun MetaLine(icon: ImageVector, text: String, contentDescription: String? = null) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = contentDescription, tint = PccColors.Text, modifier = Modifier.size(16.dp))
        Spacer(Modifier.width(8.dp))
        Text(text, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold))
    }
}


/** iOS `FeedMessageCard` (loading error / empty state). */
@Composable
fun FeedMessageCard(title: String, message: String, onRetry: (() -> Unit)? = null) {
    PccCard {
        Text(title, style = MaterialTheme.typography.titleLarge)
        Text(message, style = MaterialTheme.typography.bodyMedium)
        if (onRetry != null) {
            OutlinedButton(onClick = onRetry) { Text("Try Again") }
        }
    }
}

@Composable
fun LoadingCard(text: String = "Loading local events") {
    PccCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp, color = PccColors.PohutukawaRed)
            Spacer(Modifier.width(12.dp))
            Text(text, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.fillMaxWidth(),
        colors = ButtonDefaults.buttonColors(containerColor = PccColors.PohutukawaRed, contentColor = Color.White),
    ) { Text(text, fontWeight = FontWeight.Bold) }
}
