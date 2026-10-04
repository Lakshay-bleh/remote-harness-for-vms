package io.visey.remoteharness;

import android.accessibilityservice.AccessibilityService;
import android.accessibilityservice.GestureDescription;
import android.content.Intent;
import android.graphics.Path;
import android.graphics.Rect;
import android.os.Build;
import android.os.Bundle;
import android.view.accessibility.AccessibilityEvent;
import android.view.accessibility.AccessibilityNodeInfo;

import java.util.List;
import java.util.Locale;

/**
 * Lets Escanor use the phone the way a person does: go home or back, open the notification shade, scroll, tap what is on the
 * screen by its words, and type. It exists only because the person turned it on in Android's Accessibility settings, and it does
 * nothing on its own: every action is one the person just asked for, by voice or in the app.
 *
 * It never reads or stores what is on the screen except when the person asks "what is on my screen", and that text goes only into
 * the spoken answer on this phone.
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

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        // Nothing is read as it happens: this service only acts when asked.
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
