package com.gymapp.android

import android.app.Application
import com.gymapp.android.notifications.ReminderScheduler

class FormaApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        ReminderScheduler.createChannels(this)
    }
}
