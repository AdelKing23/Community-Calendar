package com.atlasdigital.coastcalendar.ui.components

import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.compositionLocalOf
import com.atlasdigital.coastcalendar.core.di.AppContainer
import com.atlasdigital.coastcalendar.data.repository.UserSession

/** App-wide values for shared cards (inline poll voting needs the container and the signed-in user). */
val LocalAppContainer = staticCompositionLocalOf<AppContainer?> { null }
val LocalUserSession = compositionLocalOf<UserSession?> { null }
