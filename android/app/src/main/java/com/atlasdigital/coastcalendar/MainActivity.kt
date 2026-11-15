package com.atlasdigital.coastcalendar

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.atlasdigital.coastcalendar.ui.navigation.CoastCalendarRoot
import com.atlasdigital.coastcalendar.ui.theme.CoastCalendarTheme
import com.atlasdigital.coastcalendar.ui.theme.PccColors
import androidx.compose.ui.graphics.toArgb

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Light only, like iOS: dark system icons on the cream background.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.light(PccColors.Cream.toArgb(), PccColors.Cream.toArgb()),
            navigationBarStyle = SystemBarStyle.light(PccColors.Cream.toArgb(), PccColors.Cream.toArgb()),
        )
        val container = (application as CoastCalendarApp).container
        setContent {
            CoastCalendarTheme {
                CoastCalendarRoot(container)
            }
        }
    }
}
