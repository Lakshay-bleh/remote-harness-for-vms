package com.escanorlabs.escanor

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var device: EscanorDevicePlugin? = null

    companion object {
        @Volatile
        private var foreground = false

        /** Whether the app is showing right now (the wake word opens voice mode itself then, and raises a notification otherwise). */
        @JvmStatic
        fun isForeground(): Boolean = foreground
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The phone-side tools of the Escanor voice assistant (apps, calls, alarms, torch, volume, settings, phone control, "Hey Escanor").
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EscanorDevicePlugin.CHANNEL)
        device = EscanorDevicePlugin(this, channel).also { channel.setMethodCallHandler(it) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        device?.detach()
        device = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        EscanorDevicePlugin.noteVoiceLink(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // escanor://voice: the "Hey! I'm listening" notification (or, with phone control on, WakeAction directly) brought the app forward. Voice mode opens.
        if (EscanorDevicePlugin.noteVoiceLink(intent)) device?.voiceLinkArrived()
    }

    override fun onResume() {
        super.onResume()
        foreground = true
        // "Hey! I'm listening" has done its job once the app is in front.
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(WakeAction.ID_HEARD)
    }

    override fun onPause() {
        foreground = false
        super.onPause()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        device?.onPermissionResult(requestCode)
    }
}
