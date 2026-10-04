package io.visey.remoteharness;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.core.app.NotificationCompat;

/**
 * What happens when "Hey Escanor" is heard. If the app is open and showing it opens voice mode itself. Otherwise Android does not let
 * a background service simply start an activity, so this uses what it does allow, best first:
 *  1. with "Display over other apps" allowed, a small Escanor logo appears (that is what makes opening the app permitted) and the
 *     app opens straight into listening;
 *  2. a heads-up notification that opens voice mode, which also takes over the screen when the phone is locked or idle if "Full-screen
 *     notifications" is allowed.
 * Both are cancelled as soon as the app is in front.
 */
final class WakeAction {
    private WakeAction() {}

    static final int ID_HEARD = 4102;

    static Intent voiceIntent(Context c) {
        return new Intent(Intent.ACTION_VIEW, Uri.parse("escanor://voice")).setPackage(c.getPackageName()).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
    }

    static boolean canOverlay(Context c) {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(c);
    }

    static boolean canFullScreen(Context c) {
        if (Build.VERSION.SDK_INT < 34) return true; // before Android 14 the permission in the manifest is enough
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        return nm != null && nm.canUseFullScreenIntent();
    }

    /** The phrase was heard (or the person asked for a test). */
    static void fire(Context c) {
        Context app = c.getApplicationContext();
        buzz(app);
        // The app is open: it opens voice mode itself.
        if (MainActivity.isForeground() && EscanorDevicePlugin.notifyWake()) return;
        Intent open = voiceIntent(app);
        boolean opened = canOverlay(app) && openWithLogo(app, open);
        notifyHeard(app, open, opened);
    }

    private static void buzz(Context c) {
        Vibrator v = (Vibrator) c.getSystemService(Context.VIBRATOR_SERVICE);
        if (v == null) return;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) v.vibrate(VibrationEffect.createOneShot(60, VibrationEffect.DEFAULT_AMPLITUDE));
        else v.vibrate(60);
    }

    private static void notifyHeard(Context c, Intent open, boolean alreadyOpening) {
        WakeWordService.ensureChannels(c);
        PendingIntent pi = PendingIntent.getActivity(c, 3, open, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        NotificationCompat.Builder b = new NotificationCompat.Builder(c, WakeWordService.CHANNEL_HEARD)
            .setSmallIcon(R.drawable.ic_stat_escanor)
            .setContentTitle("Hey! I’m listening")
            .setContentText("Tap to talk to Escanor.")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setTimeoutAfter(20000);
        if (!alreadyOpening && canFullScreen(c)) b.setFullScreenIntent(pi, true);
        Notification n = b.build();
        ((NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE)).notify(ID_HEARD, n);
    }

    /** Show the logo, and with it Android lets the app open from the background. Returns whether it tried. */
    private static boolean openWithLogo(Context c, Intent open) {
        final Handler ui = new Handler(Looper.getMainLooper());
        ui.post(() -> {
            WindowManager wm = (WindowManager) c.getSystemService(Context.WINDOW_SERVICE);
            View logo = null;
            try {
                logo = logo(c);
                wm.addView(logo, params());
            } catch (Exception e) {
                logo = null; // no overlay: the notification still works
            }
            try {
                c.startActivity(open);
            } catch (Exception ignored) {
                // Android refused: the notification is the way in
            }
            final View shown = logo;
            if (shown != null) ui.postDelayed(() -> {
                try {
                    wm.removeView(shown);
                } catch (Exception ignored) {
                    // already gone
                }
            }, 2500);
        });
        return true;
    }

    private static WindowManager.LayoutParams params() {
        int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY : WindowManager.LayoutParams.TYPE_PHONE;
        WindowManager.LayoutParams lp = new WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT, WindowManager.LayoutParams.WRAP_CONTENT, type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT);
        lp.gravity = Gravity.TOP | Gravity.CENTER_HORIZONTAL;
        lp.y = 160;
        return lp;
    }

    private static View logo(Context c) {
        float d = c.getResources().getDisplayMetrics().density;
        LinearLayout row = new LinearLayout(c);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        int pad = (int) (10 * d);
        row.setPadding(pad, pad, (int) (18 * d), pad);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(0xF2171717);
        bg.setCornerRadius(40 * d);
        row.setBackground(bg);
        ImageView icon = new ImageView(c);
        icon.setImageResource(R.mipmap.ic_launcher_round);
        row.addView(icon, new LinearLayout.LayoutParams((int) (44 * d), (int) (44 * d)));
        TextView t = new TextView(c);
        t.setText("Listening…");
        t.setTextColor(0xFFFFFFFF);
        t.setTextSize(16);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setPadding((int) (12 * d), 0, 0, 0);
        row.addView(t);
        return row;
    }
}
