package com.presbyfriend.service

import android.content.Intent
import android.service.quicksettings.TileService
import com.presbyfriend.MainActivity

class QuickSettingsTileService : TileService() {

    override fun onClick() {
        super.onClick()
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra("launch_magnifier", true)
        startActivityAndCollapse(intent)
    }
}
