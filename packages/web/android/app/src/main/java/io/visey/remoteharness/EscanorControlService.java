package io.visey.remoteharness;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.GestureDescription;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Path;
import android.graphics.Rect;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

import androidx.core.app.NotificationCompat;

import java.util.List;
import java.util.Locale;

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
 */
public class EscanorControlService extends AccessibilityService {

    private static volatile EscanorControlService instance;

    /** Is the person's permission in place (the service is switched on and connected)? */
    public static boolean isRunning() {
        return instance != null;
    }

    public static EscanorControlService get() {
        return instance;
    }

    @Override
    protected void onServiceConnected() {
        instance = this;
    }

    static final String CHANNEL_PAUSED = "escanor_control";
    static final int ID_PAUSED = 4103;

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        // Nothing on screen is read as it happens: this service only acts when asked. All it looks at is which app came to the front,
        // to step aside for payment apps.
        if (event == null || event.getEventType() != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED || event.getPackageName() == null) return;
        String pkg = event.getPackageName().toString();
        if (PaymentApps.isPaymentApp(pkg)) stepAsideFor(pkg);
    }

    /** Switch off so `pkg` (a payment app) works, and say so in a notification that opens the switch again. */
    private void stepAsideFor(String pkg) {
        notifyPaused(this, appLabel(this, pkg));
        turnOff();
    }

    /** The person (or a payment app opening) switched phone control off. Turning it on again happens only in Android's settings. */
    public void turnOff() {
        instance = null;
        disableSelf();
    }

    private static String appLabel(Context c, String pkg) {
        try {
            PackageManager pm = c.getPackageManager();
            return pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString();
        } catch (Exception e) {
            return "your payment app";
        }
    }

    private static void notifyPaused(Context c, String app) {
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) return;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(new NotificationChannel(CHANNEL_PAUSED, "Phone control switched off", NotificationManager.IMPORTANCE_DEFAULT));
        }
        Intent settings = new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent pi = PendingIntent.getActivity(c, 5, settings, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        nm.notify(ID_PAUSED, new NotificationCompat.Builder(c, CHANNEL_PAUSED)
            .setSmallIcon(R.drawable.ic_stat_escanor)
            .setContentTitle("Phone control is off so " + app + " works")
            .setContentText("Payment apps do not run while it is on. When you are done, tap to switch it back on.")
            .setStyle(new NotificationCompat.BigTextStyle().bigText("Payment and banking apps do not run while another app can control the phone. When you are done in " + app + ", tap here and switch Escanor back on."))
            .setContentIntent(pi)
            .setAutoCancel(true)
            .build());
    }

    @Override
    public void onInterrupt() {}

    @Override
    public boolean onUnbind(Intent intent) {
        instance = null;
        return super.onUnbind(intent);
    }

    @Override
    public void onDestroy() {
        instance = null;
        super.onDestroy();
    }

    // ------------------------------------------------------------------ system buttons

    /** home, back, recents, notifications, quick_settings, lock, screenshot, power. False if this Android cannot do it. */
    public boolean global(String name) {
        int action;
        switch (name == null ? "" : name) {
            case "home": action = GLOBAL_ACTION_HOME; break;
            case "back": action = GLOBAL_ACTION_BACK; break;
            case "recents": action = GLOBAL_ACTION_RECENTS; break;
            case "notifications": action = GLOBAL_ACTION_NOTIFICATIONS; break;
            case "quick_settings": action = GLOBAL_ACTION_QUICK_SETTINGS; break;
            case "power": action = GLOBAL_ACTION_POWER_DIALOG; break;
            case "lock":
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false;
                action = GLOBAL_ACTION_LOCK_SCREEN;
                break;
            case "screenshot":
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return false;
                action = GLOBAL_ACTION_TAKE_SCREENSHOT;
                break;
            default: return false;
        }
        return performGlobalAction(action);
    }

    // ------------------------------------------------------------------ what is on the screen

    private static boolean visible(AccessibilityNodeInfo n) {
        return n != null && n.isVisibleToUser();
    }

    /** Press whatever on screen is called `text` (an exact label first, then one that contains it). */
    public boolean clickText(String text) {
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null || text == null || text.trim().isEmpty()) return false;
        String want = text.trim().toLowerCase(Locale.ROOT);
        List<AccessibilityNodeInfo> found = root.findAccessibilityNodeInfosByText(text.trim());
        AccessibilityNodeInfo best = null;
        for (AccessibilityNodeInfo n : found) {
            if (!visible(n)) continue;
            CharSequence label = n.getText() != null ? n.getText() : n.getContentDescription();
            if (label != null && label.toString().trim().toLowerCase(Locale.ROOT).equals(want)) {
                best = n;
                break;
            }
            if (best == null) best = n;
        }
        for (AccessibilityNodeInfo n = best; n != null; n = n.getParent()) {
            if (n.isClickable() && n.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return true;
        }
        if (best != null) {
            // not clickable itself and nothing above it is: tap where it is
            Rect r = new Rect();
            best.getBoundsInScreen(r);
            return tap(r.centerX(), r.centerY());
        }
        return false;
    }

    private static AccessibilityNodeInfo firstScrollable(AccessibilityNodeInfo node) {
        if (node == null) return null;
        if (node.isScrollable() && visible(node)) return node;
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo found = firstScrollable(node.getChild(i));
            if (found != null) return found;
        }
        return null;
    }

    /** Scroll the first scrollable thing on screen: forward is "down the page". */
    public boolean scroll(boolean forward) {
        AccessibilityNodeInfo target = firstScrollable(getRootInActiveWindow());
        if (target == null) return false;
        return target.performAction(forward ? AccessibilityNodeInfo.ACTION_SCROLL_FORWARD : AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD);
    }

    private static AccessibilityNodeInfo firstEditable(AccessibilityNodeInfo node) {
        if (node == null) return null;
        if (node.isEditable() && visible(node)) return node;
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo found = firstEditable(node.getChild(i));
            if (found != null) return found;
        }
        return null;
    }

    /** Type into the field that has the cursor (or the first text field on screen), after what is already there. */
    public boolean typeText(String text) {
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null || text == null) return false;
        AccessibilityNodeInfo field = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
        if (field == null || !field.isEditable()) field = firstEditable(root);
        if (field == null) return false;
        CharSequence current = field.getText();
        String merged = (current == null ? "" : current.toString()) + text;
        Bundle args = new Bundle();
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, merged);
        return field.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args);
    }

    /** A tap at a point on the screen. */
    public boolean tap(int x, int y) {
        Path p = new Path();
        p.moveTo(x, y);
        GestureDescription g = new GestureDescription.Builder().addStroke(new GestureDescription.StrokeDescription(p, 0, 60)).build();
        return dispatchGesture(g, null, null);
    }

    private static void collect(AccessibilityNodeInfo node, StringBuilder out, int max) {
        if (node == null || out.length() >= max || !visible(node)) return;
        CharSequence t = node.getText() != null ? node.getText() : node.getContentDescription();
        if (t != null && t.toString().trim().length() > 0 && !node.isPassword()) {
            if (out.length() > 0) out.append(". ");
            out.append(t.toString().trim());
        }
        for (int i = 0; i < node.getChildCount(); i++) collect(node.getChild(i), out, max);
    }

    /** The words visible on screen, in reading order, cut to `max` characters. Password fields are never included. */
    public String readScreen(int max) {
        AccessibilityNodeInfo root = getRootInActiveWindow();
        if (root == null) return "";
        StringBuilder out = new StringBuilder();
        collect(root, out, max);
        return out.length() > max ? out.substring(0, max) : out.toString();
    }
}
