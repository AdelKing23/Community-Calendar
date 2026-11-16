package com.atlasdigital.coastcalendar.feature.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.SubcomposeAsyncImage
import com.atlasdigital.coastcalendar.data.model.EventImage
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import com.atlasdigital.coastcalendar.ui.theme.PccShapes

/** iOS `ListingRemoteImageView`: signed URL image, placeholder while loading or if missing/failed. */
@Composable
fun ListingRemoteImage(
    image: EventImage?,
    isPoll: Boolean,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.FillWidth,
) {
    val url = image?.signedUrl
    if (url == null) {
        ListingImagePlaceholder(isPoll, modifier)
        return
    }
    SubcomposeAsyncImage(
        model = url,
        contentDescription = null,
        contentScale = contentScale,
        modifier = modifier.fillMaxWidth().clip(PccShapes.Small),
        loading = { ListingImagePlaceholder(isPoll) },
        error = { ListingImagePlaceholder(isPoll) },
    )
}

/** iOS `EventImagePlaceholderView` / `PollImagePlaceholderView`. */
@Composable
fun ListingImagePlaceholder(isPoll: Boolean, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 138.dp)
            .clip(PccShapes.Small)
            .background(if (isPoll) PccColors.LeafGreen.copy(alpha = 0.10f) else PccColors.Cream.copy(alpha = 0.78f)),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(24.dp)) {
            Text(if (isPoll) "Community poll" else "Coast Calendar", style = MaterialTheme.typography.titleLarge)
            Text(if (isPoll) "Have your say" else "Local listing", style = MaterialTheme.typography.labelLarge, color = PccColors.Text)
        }
    }
}

@Composable
fun Capsule(text: String, background: Color, foreground: Color, modifier: Modifier = Modifier) {
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        color = foreground,
        maxLines = 1,
        modifier = modifier.clip(CircleShape).background(background).padding(horizontal = 10.dp, vertical = 6.dp),
    )
}

/** iOS `EventInfoRow` / `OrganiserContactRow` (tappable when [onClick] is set). */
@Composable
fun InfoRow(icon: ImageVector, title: String, value: String, onClick: (() -> Unit)? = null) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .clip(PccShapes.Small)
            .let { if (onClick != null) it.clickable(onClick = onClick) else it }
            .padding(vertical = 2.dp),
    ) {
        Box(
            Modifier.size(38.dp).clip(PccShapes.Small).background(PccColors.Cream),
            contentAlignment = Alignment.Center,
        ) { Icon(icon, contentDescription = null, tint = PccColors.PohutukawaOrange, modifier = Modifier.size(20.dp)) }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.labelMedium, color = PccColors.Text)
            Text(
                value,
                style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Bold),
                color = if (onClick != null) PccColors.LeafGreen else PccColors.Ink,
            )
        }
    }
}

/** iOS `EngagementButton`. */
@Composable
fun EngagementButton(title: String, icon: ImageVector, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
            .clip(PccShapes.Small)
            .background(if (selected) PccColors.LeafGreen else PccColors.Cream.copy(alpha = 0.66f))
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp, horizontal = 4.dp),
    ) {
        val tint = if (selected) Color.White else PccColors.Text
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
        Text(title, fontSize = 11.sp, fontWeight = FontWeight.Black, color = tint, maxLines = 1)
    }
}

@Composable
fun EngagementRow(
    interested: Boolean,
    going: Boolean,
    saved: Boolean,
    onInterested: () -> Unit,
    onGoing: () -> Unit,
    onSave: () -> Unit,
    onShare: () -> Unit,
) {
    Row(horizontalArrangement = Arrangement.spacedBy(5.dp), modifier = Modifier.fillMaxWidth()) {
        EngagementButton("Interested", Icons.Filled.Star, interested, Modifier.weight(1f), onInterested)
        EngagementButton("Going", Icons.Filled.CheckCircle, going, Modifier.weight(1f), onGoing)
        EngagementButton("Save", if (saved) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder, saved, Modifier.weight(1f), onSave)
        EngagementButton("Share", Icons.Filled.Share, false, Modifier.weight(1f), onShare)
    }
}

/** iOS `PollOptionButton`: option, count pill and orange bar once anyone has answered. */
@Composable
fun PollOptionButton(
    title: String,
    count: Int,
    total: Int,
    selected: Boolean,
    enabled: Boolean,
    subtitle: String? = null,
    onClick: () -> Unit,
) {
    val pct = if (total > 0) count.toFloat() / total else 0f
    Column(
        verticalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier
            .fillMaxWidth()
            .clip(PccShapes.Small)
            .background(Color.White.copy(alpha = if (selected) 0.86f else 0.68f))
            .border(1.dp, if (selected) PccColors.PohutukawaOrange.copy(alpha = 0.48f) else PccColors.Text.copy(alpha = 0.12f), PccShapes.Small)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(11.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Bold), color = PccColors.Ink)
                subtitle?.let { Text(it, style = MaterialTheme.typography.labelMedium, color = PccColors.Text) }
            }
            if (selected) Icon(Icons.Filled.CheckCircle, contentDescription = "Your answer", tint = PccColors.PohutukawaOrange, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Capsule("$count", Color.White.copy(alpha = 0.82f), PccColors.Text)
        }
        if (total > 0) {
            LinearProgressIndicator(
                progress = { pct },
                color = PccColors.PohutukawaOrange.copy(alpha = 0.72f),
                trackColor = PccColors.Ink.copy(alpha = 0.08f),
                drawStopIndicator = {},
                modifier = Modifier.fillMaxWidth().clip(CircleShape),
            )
        }
    }
}
