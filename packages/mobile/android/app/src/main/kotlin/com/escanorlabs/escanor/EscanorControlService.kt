package com.escanorlabs.escanor

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.core.app.NotificationCompat
import java.util.Locale

/**
 * Lets Escanor use the phone the way a person does: go home or back, open the notification shade, scroll, tap what is on the
 * screen by its words, and type. It exists only because the person turned it on in Android's Accessibility settings, and it does
 * nothing on its own: every action is one the person just asked for, by voice or in the app.
 *
 * It never reads or stores what is on the screen except when the person asks "what is on my screen", and that text goes only into
 * the spoken answer on this phone.
 *
 * Payment and banking apps refuse to run while any accessibility service is on, so when one of them opens this switches itself off
 * (Android lets a service do that, not switch itself back on) and leaves a notification that leads back to the switch.
 *
 * The class is always compiled, but it is DECLARED only in the "with phone control" and Play builds (src/phonecontrol, src/play):
 * Play Protect blocks sideloaded apps that declare an accessibility service, so the normal download leaves the declaration out.
 */
class EscanorControlService : AccessibilityService() {

    companion object {
        const val CHANNEL_PAUSED = "escanor_control"
        const val ID_PAUSED = 4103

        @Volatile
        private var instance: EscanorControlService? = null

        /** Is the person's permission in place (the service is switched on and connected)? */
        @JvmStatic
        fun isRunning(): Boolean = instance != null

        @JvmStatic
        fun get(): EscanorControlService? = instance

        private fun visible(n: AccessibilityNodeInfo?): Boolean = n != null && n.isVisibleToUser

        private fun firstScrollable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            if (node == null) return null
            if (node.isScrollable && visible(node)) return node
            for (i in 0 until node.childCount) firstScrollable(node.getChild(i))?.let { return it }
            return null
        }

        private fun firstEditable(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            if (node == null) return null
            if (node.isEditable && visible(node)) return node
            for (i in 0 until node.childCount) firstEditable(node.getChild(i))?.let { return it }
            return null
        }

        private fun collect(node: AccessibilityNodeInfo?, out: StringBuilder, max: Int) {
            if (node == null || out.length >= max || !visible(node)) return
            val t = node.text ?: node.contentDescription
            if (t != null && t.toString().trim().isNotEmpty() && !node.isPassword) {
                if (out.isNotEmpty()) out.append(". ")
                out.append(t.toString().trim())
            }
            for (i in 0 until node.childCount) collect(node.getChild(i), out, max)
        }

        private fun appLabel(c: Context, pkg: String): String = try {
            val pm = c.packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
        } catch (e: Exception) {
            "your payment app"
        }

        private fun notifyPaused(c: Context, app: String) {
            val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager? ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                nm.createNotificationChannel(NotificationChannel(CHANNEL_PAUSED, "Phone control switched off", NotificationManager.IMPORTANCE_DEFAULT))
            }
            val settings = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            val pi = PendingIntent.getActivity(c, 5, settings, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val n = NotificationCompat.Builder(c, CHANNEL_PAUSED)
                .setSmallIcon(R.drawable.ic_stat_escanor)
                .setContentTitle("Phone control is off so $app works")
                .setContentText("Payment apps do not run while it is on. When you are done, tap to switch it back on.")
                .setStyle(
                    NotificationCompat.BigTextStyle().bigText(
                        "Payment and banking apps do not run while another app can control the phone. When you are done in $app, tap here and switch Escanor back on.",
                    ),
                )
                .setContentIntent(pi)
                .setAutoCancel(true)
                .build()
            try {
                nm.notify(ID_PAUSED, n)
            } catch (e: SecurityException) {
                // notifications not allowed: phone control is still switched off
            }
        }
    }

    override fun onServiceConnected() {
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Nothing on screen is read as it happens: this service only acts when asked. All it looks at is which app came to the front,
        // to step aside for payment apps.
        if (event == null || event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (PaymentApps.isPaymentApp(pkg)) stepAsideFor(pkg)
    }

    /** Switch off so `pkg` (a payment app) works, and say so in a notification that opens the switch again. */
    private fun stepAsideFor(pkg: String) {
        notifyPaused(this, appLabel(this, pkg))
        turnOff()
    }

    /** The person (or a payment app opening) switched phone control off. Turning it on again happens only in Android's settings. */
    fun turnOff() {
        instance = null
        disableSelf()
    }

    override fun onInterrupt() {}

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    // ------------------------------------------------------------------ system buttons

    /** home, back, recents, notifications, quick_settings, lock, screenshot, power. False if this Android cannot do it. */
    fun global(name: String?): Boolean {
        val action = when (name ?: "") {
            "home" -> GLOBAL_ACTION_HOME
            "back" -> GLOBAL_ACTION_BACK
            "recents" -> GLOBAL_ACTION_RECENTS
            "notifications" -> GLOBAL_ACTION_NOTIFICATIONS
            "quick_settings" -> GLOBAL_ACTION_QUICK_SETTINGS
            "power" -> GLOBAL_ACTION_POWER_DIALOG
            "lock" -> if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false else GLOBAL_ACTION_LOCK_SCREEN
            "screenshot" -> if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false else GLOBAL_ACTION_TAKE_SCREENSHOT
            else -> return false
        }
        return performGlobalAction(action)
    }

    // ------------------------------------------------------------------ what is on the screen

    /** Press whatever on screen is called `text` (an exact label first, then one that contains it). */
    fun clickText(text: String?): Boolean {
        val root = rootInActiveWindow
        if (root == null || text == null || text.trim().isEmpty()) return false
        val want = text.trim().lowercase(Locale.ROOT)
        var best: AccessibilityNodeInfo? = null
        for (n in root.findAccessibilityNodeInfosByText(text.trim())) {
            if (!visible(n)) continue
            val label = n.text ?: n.contentDescription
            if (label != null && label.toString().trim().lowercase(Locale.ROOT) == want) {
                best = n
                break
            }
            if (best == null) best = n
        }
        var n = best
        while (n != null) {
            if (n.isClickable && n.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true
            n = n.parent
        }
        if (best != null) {
            // not clickable itself and nothing above it is: tap where it is
            val r = Rect()
            best.getBoundsInScreen(r)
            return tap(r.centerX(), r.centerY())
        }
        return false
    }

    /** Scroll the first scrollable thing on screen: forward is "down the page". */
    fun scroll(forward: Boolean): Boolean {
        val target = firstScrollable(rootInActiveWindow) ?: return false
        return target.performAction(if (forward) AccessibilityNodeInfo.ACTION_SCROLL_FORWARD else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD)
    }

    /** Type into the field that has the cursor (or the first text field on screen), after what is already there. */
    fun typeText(text: String?): Boolean {
        val root = rootInActiveWindow
        if (root == null || text == null) return false
        var field = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (field == null || !field.isEditable) field = firstEditable(root)
        if (field == null) return false
        val merged = (field.text?.toString() ?: "") + text
        val args = Bundle()
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, merged)
        return field.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    /** A tap at a point on the screen. */
    fun tap(x: Int, y: Int): Boolean {
        val p = Path()
        p.moveTo(x.toFloat(), y.toFloat())
        val g = GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(p, 0, 60)).build()
        return dispatchGesture(g, null, null)
    }

    /** The words visible on screen, in reading order, cut to `max` characters. Password fields are never included. */
    fun readScreen(max: Int): String {
        val root = rootInActiveWindow ?: return ""
        val out = StringBuilder()
        collect(root, out, max)
        return if (out.length > max) out.substring(0, max) else out.toString()
    }
}
