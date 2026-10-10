package com.escanorlabs.escanor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import java.io.File

/**
 * Listens for "Hey Escanor" in the background, only while the person has turned that on. The words are recognised on the phone
 * by a small speech model; nothing is recorded or sent anywhere, and the microphone audio is thrown away as it is heard. A
 * notification says it is listening, as Android requires, and turning the switch off stops it.
 *
 * When the phrase is heard the service stops listening (the voice assistant needs the microphone), tells the app if it is open,
 * and otherwise raises a notification that opens the app straight into voice mode.
 */
class WakeWordService : Service() {
    private var speech: SpeechService? = null
    private var model: Model? = null
    private var lastHeard = 0L

    companion object {
        const val ACTION_STOP = "com.escanorlabs.escanor.WAKE_STOP"
        const val CHANNEL_LISTENING = "escanor_wake_listening"
        const val CHANNEL_HEARD = "escanor_wake_heard"
        private const val ID_LISTENING = 4101
        private const val HEARD_HOLD_MS = 25000L

        @Volatile
        private var running = false

        /** The app has the microphone (voice mode is open). */
        @Volatile
        private var appHolds = false

        /** The phrase was just heard and the app has not taken over yet: stop listening, but only for a little while. */
        @Volatile
        private var heardHold = false

        @Volatile
        private var current: WakeWordService? = null

        /**
         * Speech recognisers write "Escanor" as it sounds: "escaner", "is canon", "ex canner". A small word list (the phrases this
         * model really produces for it) is what the recogniser is allowed to say, and this pattern accepts them.
         */
        val HEARD = Regex("\\b(?:hey|hay|hi|okay|ok|a)\\s+(?:es+\\s?ca+n+[eo]r?|ex\\s?can+[eo]r?|is\\s?can+[eo]r?|e\\s?scan+[eo]r?|escape\\s?her|es\\s?canon|escanor)\\b")
        private const val GRAMMAR =
            "[\"hey escanor\", \"hey escaner\", \"hey is canon\", \"hey escape her\", \"hey e scanner\", \"hey es canon\", \"hey scanner\", \"okay escaner\", \"[unk]\"]"

        @JvmStatic
        fun isRunning(): Boolean = running

        /** Where the downloaded speech model lives. */
        @JvmStatic
        fun modelDir(c: Context): File = File(c.filesDir, "vosk-model-small-en-us-0.15")

        @JvmStatic
        fun modelReady(c: Context): Boolean = File(modelDir(c), "am/final.mdl").exists()

        private fun paused() = appHolds || heardHold

        private fun apply() {
            current?.speech?.setPause(paused())
        }

        /** The app is using the microphone (voice mode): stop listening for the phrase until it is done. */
        @JvmStatic
        fun pause(p: Boolean) {
            appHolds = p
            if (p) heardHold = false // the app has taken over: its own hold is the one that counts now
            apply()
        }

        @JvmStatic
        fun ensureChannels(c: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(NotificationChannel(CHANNEL_LISTENING, "Listening for Hey Escanor", NotificationManager.IMPORTANCE_MIN))
            nm.createNotificationChannel(NotificationChannel(CHANNEL_HEARD, "Hey Escanor heard", NotificationManager.IMPORTANCE_HIGH))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        ensureChannels(this)
        val stop = Intent(this, WakeWordService::class.java).setAction(ACTION_STOP)
        val stopPi = PendingIntent.getService(this, 1, stop, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val open = Intent(this, MainActivity::class.java).setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val openPi = PendingIntent.getActivity(this, 2, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n: Notification = NotificationCompat.Builder(this, CHANNEL_LISTENING)
            .setSmallIcon(R.drawable.ic_stat_escanor)
            .setContentTitle("Listening for “Hey Escanor”")
            .setContentText("Heard on this phone only. Nothing is recorded.")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setContentIntent(openPi)
            .addAction(0, "Turn off", stopPi)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) startForeground(ID_LISTENING, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        else startForeground(ID_LISTENING, n)

        if (!running) {
            running = true
            current = this
            Thread({ load() }, "escanor-wake-load").start()
        }
        return START_STICKY
    }

    private fun load() {
        try {
            if (!modelReady(this)) {
                stopSelf()
                return
            }
            val m = Model(modelDir(this).absolutePath)
            model = m
            val rec = Recognizer(m, 16000.0f, GRAMMAR)
            val s = SpeechService(rec, 16000.0f)
            speech = s
            s.setPause(paused())
            s.startListening(object : RecognitionListener {
                override fun onPartialResult(hypothesis: String?) = check(hypothesis, "partial")
                override fun onResult(hypothesis: String?) = check(hypothesis, "text")
                override fun onFinalResult(hypothesis: String?) = check(hypothesis, "text")
                override fun onError(e: Exception?) = stopSelf()
                override fun onTimeout() {}
            })
        } catch (e: Exception) {
            stopSelf()
        }
    }

    private fun check(json: String?, field: String) {
        if (paused() || json == null) return
        try {
            val said = JSONObject(json).optString(field, "").lowercase()
            if (said.isEmpty() || !HEARD.containsMatchIn(said)) return
            val now = System.currentTimeMillis()
            if (now - lastHeard < 4000) return // one phrase is heard as several results
            lastHeard = now
            heard()
        } catch (ignored: Exception) {
            // not a result we understand: keep listening
        }
    }

    private fun heard() {
        // The assistant needs the microphone now. If the app takes over it holds the pause itself; if it never does (the person
        // ignored the notification) listening comes back by itself after a while, so one missed "Hey Escanor" is not the last.
        heardHold = true
        apply()
        Handler(Looper.getMainLooper()).postDelayed({
            heardHold = false
            apply()
        }, HEARD_HOLD_MS)
        WakeAction.fire(this)
    }

    override fun onDestroy() {
        running = false
        current = null
        try {
            speech?.stop()
            speech?.shutdown()
            model?.close()
        } catch (ignored: Exception) {
            // already gone
        }
        super.onDestroy()
    }
}
