package com.presbyfriend

import android.app.Application
import com.presbyfriend.core.storage.SettingsDataStore

class PresbyFriendApp : Application() {
    lateinit var settingsStore: SettingsDataStore
        private set

    override fun onCreate() {
        super.onCreate()
        settingsStore = SettingsDataStore(this)
    }
}
