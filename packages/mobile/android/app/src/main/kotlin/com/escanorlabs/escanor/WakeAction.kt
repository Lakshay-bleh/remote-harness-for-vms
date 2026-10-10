package com.escanorlabs.escanor

import android.Manifest
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.core.app.NotificationCompat

/**
 * What happens when "Hey Escanor" is heard. If the app is open and showing it opens voice mode itself. Otherwise Android does not let
 * a background service simply start an activity, so this uses what it does allow, best first:
 *  1. while phone control is switched on, Android lets the app open itself, so it opens straight into listening;
 *  2. a heads-up notification that opens voice mode, which also takes over the screen when the phone is locked or idle in builds that
 *     declare full-screen notifications and where they are allowed (the normal and Play builds do not declare them).
 * It never draws over other apps: payment and banking apps refuse to run next to an app that can.
 */
object WakeAction {
    const val ID_HEARD = 4102

    fun voiceIntent(c: Context): Intent =
        Intent(Intent.ACTION_VIEW, Uri.parse("escanor://voice")).setPackage(c.packageName)
            .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)

    /** Does this build list `permission` in its manifest? (The normal download leaves out what Play Protect objects to.) */
    @JvmStatic
    @Suppress("DEPRECATION")
    fun declares(c: Context, permission: String): Boolean = try {
        val info = c.packageManager.getPackageInfo(c.packageName, PackageManager.GET_PERMISSIONS)
        info.requestedPermissions?.contains(permission) == true
    } catch (e: Exception) {
        false // not known: say no
    }

    /** Can Escanor open itself from another app or the home screen right now? Only while phone control is on. */
    @JvmStatic
    fun opensDirectly(): Boolean = EscanorControlService.isRunning()

    @JvmStatic
    fun canFullScreen(c: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !declares(c, Manifest.permission.USE_FULL_SCREEN_INTENT)) return false
        if (Build.VERSION.SDK_INT < 34) return true // before Android 14 the permission in the manifest is enough
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager?
        return nm != null && nm.canUseFullScreenIntent()
    }

    /** The phrase was heard (or the person asked for a test). */
    @JvmStatic
    fun fire(c: Context) {
        val app = c.applicationContext
        buzz(app)
        // The app is open: it opens voice mode itself.
        if (MainActivity.isForeground() && EscanorDevicePlugin.notifyWake()) return
        val open = voiceIntent(app)
        notifyHeard(app, open, openDirectly(open))
    }

    /** With phone control on, Android lets the app open from the background. Returns whether it did. */
    private fun openDirectly(open: Intent): Boolean {
        val svc = EscanorControlService.get() ?: return false
        return try {
            svc.startActivity(open)
            true
        } catch (e: Exception) {
            false // Android refused: the notification is the way in
        }
    }

    @Suppress("DEPRECATION")
    private fun buzz(c: Context) {
        val v = c.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator? ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) v.vibrate(VibrationEffect.createOneShot(60, VibrationEffect.DEFAULT_AMPLITUDE))
        else v.vibrate(60)
    }

    private fun notifyHeard(c: Context, open: Intent, alreadyOpening: Boolean) {
        WakeWordService.ensureChannels(c)
        val pi = PendingIntent.getActivity(c, 3, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val b = NotificationCompat.Builder(c, WakeWordService.CHANNEL_HEARD)
            .setSmallIcon(R.drawable.ic_stat_escanor)
            .setContentTitle("Hey! I’m listening")
            .setContentText("Tap to talk to Escanor.")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setTimeoutAfter(20000)
        if (!alreadyOpening && canFullScreen(c)) b.setFullScreenIntent(pi, true)
        try {
            (c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(ID_HEARD, b.build())
        } catch (e: SecurityException) {
            // notifications not allowed: nothing more Android lets us do
        }
    }
}
