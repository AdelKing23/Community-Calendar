package com.atlasdigital.coastcalendar

import android.app.Application
import com.atlasdigital.coastcalendar.core.di.AppContainer

class CoastCalendarApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}
