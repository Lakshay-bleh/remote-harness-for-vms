package io.visey.remoteharness;

import android.Manifest;
import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.VibrationEffect;
import android.os.Vibrator;

import androidx.core.app.NotificationCompat;

/**
 * What happens when "Hey Escanor" is heard. If the app is open and showing it opens voice mode itself. Otherwise Android does not let
 * a background service simply start an activity, so this uses what it does allow, best first:
 *  1. while phone control is switched on, Android lets the app open itself, so it opens straight into listening;
 *  2. a heads-up notification that opens voice mode, which also takes over the screen when the phone is locked or idle in builds that
 *     declare full-screen notifications and where they are allowed.
 * It never draws over other apps: payment and banking apps refuse to run next to an app that can.
 */
final class WakeAction {
    private WakeAction() {}

    static final int ID_HEARD = 4102;

    static Intent voiceIntent(Context c) {
        return new Intent(Intent.ACTION_VIEW, Uri.parse("escanor://voice")).setPackage(c.getPackageName()).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
    }

    /** Does this build list `permission` in its manifest? (The normal download leaves out what Play Protect objects to.) */
    static boolean declares(Context c, String permission) {
        try {
            PackageInfo info = c.getPackageManager().getPackageInfo(c.getPackageName(), PackageManager.GET_PERMISSIONS);
            if (info.requestedPermissions == null) return false;
            for (String p : info.requestedPermissions) if (permission.equals(p)) return true;
        } catch (Exception ignored) {
            // not known: say no
        }
        return false;
    }

    /** Can Escanor open itself from another app or the home screen right now? Only while phone control is on. */
    static boolean opensDirectly() {
        return EscanorControlService.isRunning();
    }

    static boolean canFullScreen(Context c) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !declares(c, Manifest.permission.USE_FULL_SCREEN_INTENT)) return false;
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
        notifyHeard(app, open, openDirectly(open));
    }

    /** With phone control on, Android lets the app open from the background. Returns whether it did. */
    private static boolean openDirectly(Intent open) {
        EscanorControlService svc = EscanorControlService.get();
        if (svc == null) return false;
        try {
            svc.startActivity(open);
            return true;
        } catch (Exception e) {
            return false; // Android refused: the notification is the way in
        }
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
}
