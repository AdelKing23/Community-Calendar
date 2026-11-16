package com.atlasdigital.coastcalendar.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** iOS `PCCTheme` colours (same RGB values). */
object PccColors {
    val PohutukawaRed = Color(0xFFC71A12)    // 0.78, 0.10, 0.07
    val PohutukawaOrange = Color(0xFFF05C1A) // 0.94, 0.36, 0.10
    val LeafGreen = Color(0xFF1F4D33)        // 0.12, 0.30, 0.20
    val DeepGreen = Color(0xFF0A1F1A)        // 0.04, 0.12, 0.10
    val Cream = Color(0xFFFAF2E0)            // 0.98, 0.95, 0.88
    val CreamDark = Color(0xFFF2E8D1)        // 0.95, 0.91, 0.82
    val Sand = Color(0xFFDBC299)             // 0.86, 0.76, 0.60
    val Ink = Color(0xFF1A211F)              // 0.10, 0.13, 0.12 — headings
    /** t226: the ONE colour for all secondary, body, label and meta text (#3A403E). */
    val Text = Color(0xFF3A403E)
    val CardFill = Color.White.copy(alpha = 0.94f)
}

/** iOS `PCCTopicPalette`: one dot colour per topic on the Home calendar. */
object PccTopicPalette {
    fun color(category: com.atlasdigital.coastcalendar.data.model.EventCategory): Color = Color(
        0xFF000000 or when (category) {
            com.atlasdigital.coastcalendar.data.model.EventCategory.LiveMusic -> 0x7E57C2
            com.atlasdigital.coastcalendar.data.model.EventCategory.FoodDrink -> 0xE8A317
            com.atlasdigital.coastcalendar.data.model.EventCategory.Markets -> 0xD1495B
            com.atlasdigital.coastcalendar.data.model.EventCategory.KidsFamily -> 0xF28C28
            com.atlasdigital.coastcalendar.data.model.EventCategory.Sport -> 0x2E86DE
            com.atlasdigital.coastcalendar.data.model.EventCategory.Community -> 0x2F855A
            com.atlasdigital.coastcalendar.data.model.EventCategory.Fundraisers -> 0xE05297
            com.atlasdigital.coastcalendar.data.model.EventCategory.ClassesWorkshops -> 0x1A9E9E
            com.atlasdigital.coastcalendar.data.model.EventCategory.Seniors -> 0x8D6E63
            com.atlasdigital.coastcalendar.data.model.EventCategory.ChurchMaraeCultural -> 0x5C6BC0
            com.atlasdigital.coastcalendar.data.model.EventCategory.Nightlife -> 0x2C3E70
            com.atlasdigital.coastcalendar.data.model.EventCategory.PublicNotices -> 0x6B7280
        }.toLong(),
    )
}

object PccShapes {
    val Card = RoundedCornerShape(24.dp)   // PCCTheme.cardRadius
    val Small = RoundedCornerShape(14.dp)  // PCCTheme.smallRadius
}

private val LightColors = lightColorScheme(
    primary = PccColors.PohutukawaRed,
    onPrimary = Color.White,
    secondary = PccColors.LeafGreen,
    onSecondary = Color.White,
    tertiary = PccColors.PohutukawaOrange,
    onTertiary = Color.White,
    background = PccColors.Cream,
    onBackground = PccColors.Ink,
    surface = Color.White,
    onSurface = PccColors.Ink,
    surfaceVariant = PccColors.CreamDark,
    onSurfaceVariant = PccColors.Text,
    surfaceContainer = PccColors.Cream,
    surfaceContainerHigh = Color.White,
    surfaceContainerLow = PccColors.Cream,
    outline = PccColors.Text.copy(alpha = 0.4f),
    error = PccColors.PohutukawaRed,
)

private val Serif = FontFamily.Serif

private val PccTypography = Typography().let { base ->
    base.copy(
        displaySmall = TextStyle(fontFamily = Serif, fontWeight = FontWeight.Black, fontSize = 40.sp, color = PccColors.Ink),
        headlineMedium = TextStyle(fontFamily = Serif, fontWeight = FontWeight.Black, fontSize = 28.sp, color = PccColors.Ink),
        headlineSmall = TextStyle(fontFamily = Serif, fontWeight = FontWeight.Black, fontSize = 24.sp, color = PccColors.Ink),
        titleLarge = base.titleLarge.copy(fontWeight = FontWeight.Bold, color = PccColors.Ink),
        titleMedium = base.titleMedium.copy(fontWeight = FontWeight.Bold, color = PccColors.Text),
        bodyLarge = base.bodyLarge.copy(fontWeight = FontWeight.Medium, color = PccColors.Text),
        bodyMedium = base.bodyMedium.copy(fontWeight = FontWeight.Medium, color = PccColors.Text),
        labelLarge = base.labelLarge.copy(fontWeight = FontWeight.Bold),
        labelMedium = base.labelMedium.copy(fontWeight = FontWeight.Black),
    )
}

/** Light only (iOS UIUserInterfaceStyle = Light): no dark scheme on purpose. */
@Composable
fun CoastCalendarTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = LightColors,
        typography = PccTypography,
        shapes = Shapes(small = PccShapes.Small, medium = PccShapes.Small, large = PccShapes.Card),
        content = content,
    )
}

/** iOS `PCCScreenBackground` (Original wallpaper: cream gradient; the flower ornament art is not ported yet). */
@Composable
fun PccScreenBackground(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(Color.White.copy(alpha = 0.95f), PccColors.Cream.copy(alpha = 0.95f), PccColors.CreamDark),
                ),
            ),
        content = content,
    )
}
