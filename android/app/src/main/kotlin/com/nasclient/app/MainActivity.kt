package com.nasclient.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var downloadChannel: DownloadLocationChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        downloadChannel = DownloadLocationChannel(this).also { it.configure(flutterEngine) }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == DownloadLocationChannel.REQUEST_PICK_DIR) {
            downloadChannel?.onActivityResult(requestCode, resultCode, data)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        downloadChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
