package io.visey.remoteharness;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

import androidx.core.app.NotificationCompat;

import org.json.JSONObject;
import org.vosk.Model;
import org.vosk.Recognizer;
import org.vosk.android.RecognitionListener;
import org.vosk.android.SpeechService;

import java.io.File;
import java.util.regex.Pattern;

/**
 * Listens for "Hey Escanor" in the background, only while the person has turned that on. The words are recognised on the phone
 * by a small speech model; nothing is recorded or sent anywhere, and the microphone audio is thrown away as it is heard. A
 * notification says it is listening, as Android requires, and turning the switch off stops it.
 *
 * When the phrase is heard the service stops listening (the voice assistant needs the microphone), tells the app if it is open,
 * and otherwise raises a notification that opens the app straight into voice mode.
 */
public class WakeWordService extends Service {
    static final String ACTION_STOP = "io.visey.remoteharness.WAKE_STOP";
    static final String CHANNEL_LISTENING = "escanor_wake_listening";
    static final String CHANNEL_HEARD = "escanor_wake_heard";
    private static final int ID_LISTENING = 4101;

    private static volatile boolean running = false;
    /** The app has the microphone (voice mode is open). */
    private static volatile boolean appHolds = false;
    /** The phrase was just heard and the app has not taken over yet: stop listening, but only for a little while. */
    private static volatile boolean heardHold = false;
    private static final long HEARD_HOLD_MS = 25000;

    /**
     * Speech recognisers write "Escanor" as it sounds: "escaner", "is canon", "ex canner". A small word list (the phrases this
     * model really produces for it) is what the recogniser is allowed to say, and this pattern accepts them.
     */
    static final Pattern HEARD = Pattern.compile("\\b(?:hey|hay|hi|okay|ok|a)\\s+(?:es+\\s?ca+n+[eo]r?|ex\\s?can+[eo]r?|is\\s?can+[eo]r?|e\\s?scan+[eo]r?|escape\\s?her|es\\s?canon|escanor)\\b");
    private static final String GRAMMAR = "[\"hey escanor\", \"hey escaner\", \"hey is canon\", \"hey escape her\", \"hey e scanner\", \"hey es canon\", \"hey scanner\", \"okay escaner\", \"[unk]\"]";

    private SpeechService speech;
    private Model model;
    private long lastHeard = 0;

    static boolean isRunning() {
        return running;
    }

    /** Where the downloaded speech model lives. */
    static File modelDir(Context c) {
        return new File(c.getFilesDir(), "vosk-model-small-en-us-0.15");
    }

    static boolean modelReady(Context c) {
        return new File(modelDir(c), "am/final.mdl").exists();
    }

    private static boolean paused() {
        return appHolds || heardHold;
    }

    private static void apply() {
        WakeWordService s = current;
        if (s != null && s.speech != null) s.speech.setPause(paused());
    }

    /** The app is using the microphone (voice mode): stop listening for the phrase until it is done. */
    static void pause(boolean p) {
        appHolds = p;
        if (p) heardHold = false; // the app has taken over: its own hold is the one that counts now
        apply();
    }

    private static volatile WakeWordService current;

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && ACTION_STOP.equals(intent.getAction())) {
            stopSelf();
            return START_NOT_STICKY;
        }
        ensureChannels(this);
        Intent stop = new Intent(this, WakeWordService.class).setAction(ACTION_STOP);
        PendingIntent stopPi = PendingIntent.getService(this, 1, stop, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Intent open = new Intent(this, MainActivity.class).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent openPi = PendingIntent.getActivity(this, 2, open, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification n = new NotificationCompat.Builder(this, CHANNEL_LISTENING)
            .setSmallIcon(R.drawable.ic_stat_escanor)
            .setContentTitle("Listening for “Hey Escanor”")
            .setContentText("Heard on this phone only. Nothing is recorded.")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setContentIntent(openPi)
            .addAction(0, "Turn off", stopPi)
            .build();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) startForeground(ID_LISTENING, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE);
        else startForeground(ID_LISTENING, n);

        if (!running) {
            running = true;
            current = this;
            new Thread(this::load, "escanor-wake-load").start();
        }
        return START_STICKY;
    }

    private void load() {
        try {
            if (!modelReady(this)) {
                stopSelf();
                return;
            }
            model = new Model(modelDir(this).getAbsolutePath());
            Recognizer rec = new Recognizer(model, 16000.0f, GRAMMAR);
            speech = new SpeechService(rec, 16000.0f);
            speech.setPause(paused());
            speech.startListening(new RecognitionListener() {
                @Override public void onPartialResult(String hypothesis) { check(hypothesis, "partial"); }
                @Override public void onResult(String hypothesis) { check(hypothesis, "text"); }
                @Override public void onFinalResult(String hypothesis) { check(hypothesis, "text"); }
                @Override public void onError(Exception e) { stopSelf(); }
                @Override public void onTimeout() {}
            });
        } catch (Exception e) {
            stopSelf();
        }
    }

    private void check(String json, String field) {
        if (paused()) return;
        try {
            String said = new JSONObject(json).optString(field, "").toLowerCase();
            if (said.isEmpty() || !HEARD.matcher(said).find()) return;
            long now = System.currentTimeMillis();
            if (now - lastHeard < 4000) return; // one phrase is heard as several results
            lastHeard = now;
            heard();
        } catch (Exception ignored) {
            // not a result we understand: keep listening
        }
    }

    private void heard() {
        // The assistant needs the microphone now. If the app takes over it holds the pause itself; if it never does (the person
        // ignored the notification) listening comes back by itself after a while, so one missed "Hey Escanor" is not the last.
        heardHold = true;
        apply();
        new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(() -> {
            heardHold = false;
            apply();
        }, HEARD_HOLD_MS);
        WakeAction.fire(this);
    }

    static void ensureChannels(Context c) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
        nm.createNotificationChannel(new NotificationChannel(CHANNEL_LISTENING, "Listening for Hey Escanor", NotificationManager.IMPORTANCE_MIN));
        nm.createNotificationChannel(new NotificationChannel(CHANNEL_HEARD, "Hey Escanor heard", NotificationManager.IMPORTANCE_HIGH));
    }

    @Override
    public void onDestroy() {
        running = false;
        current = null;
        try {
            if (speech != null) {
                speech.stop();
                speech.shutdown();
            }
            if (model != null) model.close();
        } catch (Exception ignored) {
            // already gone
        }
        super.onDestroy();
    }
}
