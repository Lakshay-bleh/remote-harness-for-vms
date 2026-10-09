package com.escanorlabs.escanor

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.AlarmClock
import android.provider.ContactsContract
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.zip.ZipInputStream

/**
 * What the Escanor voice assistant can do on this phone: open any installed app, open a link, dial, set alarms and timers, the
 * torch, the volume and the system settings screens. The Dart side reaches it over the "escanor/device" MethodChannel with the
 * same method names and answers as the Capacitor plugin the app had before.
 *
 * Dialing opens the dialer with the number filled in unless the person has turned on "call directly" (and allowed Android's call
 * permission), in which case the call is placed. The normal download does not declare the call permission at all (only the "with
 * phone control" and Play builds do), so there it always opens the dialer. The contacts are read only when the person asks to call someone by name, behind
 * Android's own permission prompt. Controlling the phone (home, back, scroll, tap, type) works only while the person has switched
 * Escanor on in Accessibility settings (EscanorControlService), and only in a build that includes it (see app/build.gradle.kts).
 */
class EscanorDevicePlugin(private val activity: Activity, private val channel: MethodChannel) : MethodChannel.MethodCallHandler {
    private val context: Context = activity.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val work = Executors.newSingleThreadExecutor()
    private val waiting = HashMap<Int, MutableList<() -> Unit>>()

    /** The Dart side is there to hear "wake" (voice mode is mounted). */
    @Volatile
    private var wakeListening = false

    init {
        live = this
    }

    fun detach() {
        if (live === this) live = null
        work.shutdown()
    }

    companion object {
        const val CHANNEL = "escanor/device"
        private const val REQ_CALL = 7101
        private const val REQ_CONTACTS = 7102
        private const val NEEDS_CONTROL = "Controlling your phone needs Escanor turned on in Accessibility settings."
        private const val MODEL_URL = "https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip"

        @Volatile
        private var live: EscanorDevicePlugin? = null

        @Volatile
        private var downloading = false

        @Volatile
        private var pendingVoiceLink = false

        /** Tell the app, if it is open and showing, that the phrase was heard. False when nothing is there to hear it (the service then raises a notification). */
        @JvmStatic
        fun notifyWake(): Boolean {
            val p = live ?: return false
            if (!p.wakeListening || !p.activity.hasWindowFocus()) return false
            p.main.post { p.channel.invokeMethod("wake", null) }
            return true
        }

        /** Remember that the app was opened with escanor://voice, for the Dart side to take once. */
        @JvmStatic
        fun noteVoiceLink(intent: Intent?): Boolean {
            val data = intent?.data ?: return false
            if (data.scheme != "escanor" || data.host != "voice") return false
            pendingVoiceLink = true
            return true
        }

        private fun result(ok: Boolean, message: String? = null): HashMap<String, Any?> {
            val o = HashMap<String, Any?>()
            o["ok"] = ok
            if (message != null) o["message"] = message
            return o
        }

        private fun deleteTree(f: File) {
            f.listFiles()?.forEach { deleteTree(it) }
            f.delete()
        }
    }

    fun voiceLinkArrived() {
        main.post { channel.invokeMethod("voiceLink", null) }
    }

    private fun start(intent: Intent): Boolean = try {
        activity.startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }

    private fun granted(permission: String) = ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    /** Ask Android for a permission (it shows its own prompt), then carry on whatever the answer. */
    private fun withPermission(permission: String, code: Int, then: () -> Unit) {
        if (granted(permission)) return then()
        val list = waiting.getOrPut(code) { mutableListOf() }
        list.add(then)
        if (list.size == 1) ActivityCompat.requestPermissions(activity, arrayOf(permission), code)
    }

    fun onPermissionResult(code: Int) {
        val list = waiting.remove(code) ?: return
        list.forEach { it() }
    }

    private fun reply(r: MethodChannel.Result, value: Any?) {
        if (Looper.myLooper() == Looper.getMainLooper()) r.success(value) else main.post { r.success(value) }
    }

    override fun onMethodCall(call: MethodCall, r: MethodChannel.Result) {
        try {
            when (call.method) {
                "listApps" -> listApps(r)
                "launchPackage" -> launchPackage(call, r)
                "openUrl" -> openUrl(call, r)
                // the normal download leaves the call permission out (Play Protect is wary of it); it then always opens the dialer
                "callStatus" -> r.success(hashMapOf("granted" to callAllowed(), "available" to callDeclared()))
                "requestCallPermission" -> requestCallPermission(r)
                "callNumber" -> callNumber(call, r)
                "dial" -> dial(call, r)
                "callContact" -> withPermission(Manifest.permission.READ_CONTACTS, REQ_CONTACTS) {
                    if (granted(Manifest.permission.READ_CONTACTS)) findAndDial(call, r)
                    else r.success(result(false, "Allow Escanor to read your contacts, or say the number."))
                }
                "listContacts" -> withPermission(Manifest.permission.READ_CONTACTS, REQ_CONTACTS) {
                    if (granted(Manifest.permission.READ_CONTACTS)) work.execute { reply(r, readContacts()) }
                    else r.success(result(false, "Allow Escanor to read your contacts so it can find who to call."))
                }
                "setAlarm" -> setAlarm(call, r)
                "setTimer" -> setTimer(call, r)
                "setTorch" -> setTorch(call, r)
                "setVolume" -> setVolume(call, r)
                "openSettings" -> openSettings(call, r)
                "controlStatus" -> controlStatus(r)
                "openControlSettings" -> openControlSettings(r)
                "controlTurnOff" -> {
                    // Switch phone control off from the app. Switching it back on happens only in Android's Accessibility settings.
                    EscanorControlService.get()?.turnOff()
                    r.success(result(true))
                }
                "openAppInfo" -> {
                    val info = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                    r.success(if (start(info)) result(true) else result(false, "Open Android Settings, then Apps, then Escanor."))
                }
                "control" -> control(call, r)
                "wakeStatus" -> wakeStatus(r)
                "wakeOpenFullScreenSettings" ->
                    if (Build.VERSION.SDK_INT < 34) r.success(result(true))
                    else openSettingsPage(r, Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:" + context.packageName)))
                "wakeTest" -> {
                    // Act as though "Hey Escanor" was heard in a few seconds, so the person can press Home and see what happens.
                    main.postDelayed({ WakeAction.fire(context) }, 6000)
                    r.success(result(true))
                }
                "wakeDownloadModel" -> wakeDownloadModel(r)
                "wakeStart" -> wakeStart(r)
                "wakeStop" -> {
                    context.stopService(Intent(context, WakeWordService::class.java))
                    r.success(result(true))
                }
                "wakePause" -> {
                    // Voice mode is using the microphone: stop listening for the phrase until it is done.
                    WakeWordService.pause(call.argument<Boolean>("paused") ?: true)
                    r.success(result(true))
                }
                "wakeDeleteModel" -> {
                    context.stopService(Intent(context, WakeWordService::class.java))
                    deleteTree(WakeWordService.modelDir(context))
                    r.success(result(true))
                }
                "wakeListen" -> {
                    wakeListening = call.argument<Boolean>("on") ?: false
                    r.success(null)
                }
                "takeVoiceLink" -> {
                    val had = pendingVoiceLink
                    pendingVoiceLink = false
                    r.success(had)
                }
                else -> r.notImplemented()
            }
        } catch (e: Exception) {
            r.success(result(false, "I could not do that on this phone."))
        }
    }

    // ------------------------------------------------------------------ apps

    /** Every app with a launcher icon: its label and package. Matching a spoken name to one is done in Dart (tested there). */
    private fun listApps(r: MethodChannel.Result) {
        work.execute {
            val pm = context.packageManager
            val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            val apps = pm.queryIntentActivities(launcher, 0)
                .map { hashMapOf("label" to it.loadLabel(pm).toString(), "package" to it.activityInfo.packageName) }
                .sortedWith { x, y -> x["label"]!!.compareTo(y["label"]!!, ignoreCase = true) }
            reply(r, hashMapOf("apps" to apps))
        }
    }

    private fun launchPackage(call: MethodCall, r: MethodChannel.Result) {
        val pkg = call.argument<String>("package")
        if (pkg.isNullOrEmpty()) return r.success(result(false, "No app given."))
        val intent = context.packageManager.getLaunchIntentForPackage(pkg)
        r.success(if (intent != null && start(intent)) result(true) else result(false, "That app could not be opened."))
    }

    /** Open a web link in whatever app handles it (a youtube.com link opens the YouTube app if it is installed). https only. */
    private fun openUrl(call: MethodCall, r: MethodChannel.Result) {
        val url = call.argument<String>("url") ?: ""
        if (!url.startsWith("https://")) return r.success(result(false, "Only https links can be opened."))
        r.success(if (start(Intent(Intent.ACTION_VIEW, Uri.parse(url)))) result(true) else result(false, "Nothing on this phone can open that link."))
    }

    // ------------------------------------------------------------------ calls

    private fun callAllowed() = granted(Manifest.permission.CALL_PHONE)

    /** Does this download list the call permission at all? (The normal download does not: it always opens the dialer.) */
    private fun callDeclared() = WakeAction.declares(context, Manifest.permission.CALL_PHONE)

    /** Ring the number if the call permission is there and `direct` was asked for; otherwise open the dialer with it filled in. */
    private fun placeOrDial(number: String, direct: Boolean, label: String?): HashMap<String, Any?> {
        val rang = direct && callAllowed()
        val uri = Uri.parse("tel:" + Uri.encode(number))
        val intent = if (rang) Intent(Intent.ACTION_CALL, uri) else Intent(Intent.ACTION_DIAL, uri)
        if (!start(intent)) return result(false, "This phone cannot make calls.")
        val out = result(true, label)
        out["direct"] = rang
        return out
    }

    private fun requestCallPermission(r: MethodChannel.Result) {
        if (callAllowed()) return r.success(result(true))
        if (!callDeclared()) return r.success(result(false, "This download of Escanor opens the dialer with the number filled in, and you press call."))
        withPermission(Manifest.permission.CALL_PHONE, REQ_CALL) {
            r.success(
                if (callAllowed()) result(true)
                else result(false, "Calling directly needs the Phone permission. In Android Settings, open Apps, Escanor, Permissions, and allow Phone."),
            )
        }
    }

    private val phoneNumber = Regex("\\+?[0-9]{3,20}")

    /** A number, called directly when asked to and allowed (else the dialer). */
    private fun callNumber(call: MethodCall, r: MethodChannel.Result) {
        val number = call.argument<String>("number") ?: ""
        if (!phoneNumber.matches(number)) return r.success(result(false, "That is not a phone number."))
        // a download without the call permission cannot ring: open the dialer (no prompt Android would refuse anyway)
        val direct = call.argument<Boolean>("direct") == true && callDeclared()
        if (direct && !callAllowed()) {
            withPermission(Manifest.permission.CALL_PHONE, REQ_CALL) {
                // allowed: ring; refused: open the dialer instead, and say why it did not ring
                val out = placeOrDial(number, true, null)
                if (!callAllowed() && out["ok"] == true) out["message"] = "I opened the dialer: calling directly needs the Phone permission."
                r.success(out)
            }
            return
        }
        r.success(placeOrDial(number, direct, null))
    }

    /** Opens the dialer with the number typed in. The person presses call; a misheard word never rings anyone. */
    private fun dial(call: MethodCall, r: MethodChannel.Result) {
        val number = call.argument<String>("number") ?: ""
        if (!phoneNumber.matches(number)) return r.success(result(false, "That is not a phone number."))
        r.success(if (start(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$number")))) result(true) else result(false, "This phone cannot make calls."))
    }

    /** Every contact with a phone number: name and numbers (mobile first). Matching a spoken name to one is done in Dart, on this phone. */
    private fun readContacts(): HashMap<String, Any?> {
        val byName = LinkedHashMap<String, MutableList<String>>()
        try {
            context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER,
                    ContactsContract.CommonDataKinds.Phone.TYPE,
                ),
                null, null, ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC",
            )?.use { c ->
                while (c.moveToNext() && byName.size < 5000) {
                    val name = c.getString(0) ?: continue
                    val number = c.getString(1) ?: continue
                    val numbers = byName.getOrPut(name) { mutableListOf() }
                    val digits = number.replace(Regex("[^0-9+]"), "")
                    if (digits.length >= 3 && !numbers.contains(digits)) {
                        if (c.getInt(2) == ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE) numbers.add(0, digits) else numbers.add(digits)
                    }
                }
            }
        } catch (e: SecurityException) {
            return result(false, "Escanor is not allowed to read your contacts.")
        }
        val out = result(true)
        out["contacts"] = byName.filter { it.value.isNotEmpty() }.map { hashMapOf("name" to it.key, "numbers" to it.value) }
        return out
    }

    /** Find a contact by name and open the dialer on their number (the older way; Dart now matches names itself). */
    private fun findAndDial(call: MethodCall, r: MethodChannel.Result) {
        val name = call.argument<String>("name") ?: ""
        if (name.isBlank()) return r.success(result(false, "Who should I call?"))
        val labels = ArrayList<String>()
        val numbers = ArrayList<String>()
        try {
            context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER),
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " LIKE ?",
                arrayOf("%" + name.trim() + "%"),
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC",
            )?.use { c ->
                while (c.moveToNext() && labels.size < 5) {
                    val number = c.getString(1)
                    if (number != null && !numbers.contains(number)) {
                        labels.add(c.getString(0) ?: "")
                        numbers.add(number)
                    }
                }
            }
        } catch (e: SecurityException) {
            return r.success(result(false, "Escanor is not allowed to read your contacts."))
        }
        if (numbers.isEmpty()) return r.success(result(false, "I could not find $name in your contacts."))
        // More than one match: do not guess whom to ring.
        if (numbers.size > 1) return r.success(result(false, "I found more than one: " + labels.joinToString(", ") + ". Say the full name."))
        val direct = call.argument<Boolean>("direct") == true && callAllowed()
        r.success(placeOrDial(numbers[0], direct, labels[0]))
    }

    // ------------------------------------------------------------------ clock

    private fun setAlarm(call: MethodCall, r: MethodChannel.Result) {
        val hour = call.argument<Int>("hour")
        val minute = call.argument<Int>("minute")
        if (hour == null || minute == null || hour !in 0..23 || minute !in 0..59) return r.success(result(false, "That is not a time."))
        val i = Intent(AlarmClock.ACTION_SET_ALARM)
            .putExtra(AlarmClock.EXTRA_HOUR, hour)
            .putExtra(AlarmClock.EXTRA_MINUTES, minute)
            .putExtra(AlarmClock.EXTRA_MESSAGE, "Escanor")
            .putExtra(AlarmClock.EXTRA_SKIP_UI, true)
        r.success(if (start(i)) result(true) else result(false, "No clock app could set that alarm."))
    }

    private fun setTimer(call: MethodCall, r: MethodChannel.Result) {
        val seconds = call.argument<Int>("seconds")
        if (seconds == null || seconds < 1 || seconds > 86400) return r.success(result(false, "That is not a length of time."))
        val i = Intent(AlarmClock.ACTION_SET_TIMER).putExtra(AlarmClock.EXTRA_LENGTH, seconds).putExtra(AlarmClock.EXTRA_SKIP_UI, true)
        r.success(if (start(i)) result(true) else result(false, "No clock app could start that timer."))
    }

    // ------------------------------------------------------------------ hardware

    private fun setTorch(call: MethodCall, r: MethodChannel.Result) {
        val on = call.argument<Boolean>("on") == true
        val cm = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        try {
            for (id in cm.cameraIdList) {
                val ch = cm.getCameraCharacteristics(id)
                val flash = ch.get(CameraCharacteristics.FLASH_INFO_AVAILABLE)
                val facing = ch.get(CameraCharacteristics.LENS_FACING)
                if (flash == true && facing == CameraCharacteristics.LENS_FACING_BACK) {
                    cm.setTorchMode(id, on)
                    return r.success(result(true))
                }
            }
            r.success(result(false, "This phone has no flashlight."))
        } catch (e: CameraAccessException) {
            r.success(result(false, "The flashlight is busy. Close the camera and try again."))
        } catch (e: IllegalArgumentException) {
            r.success(result(false, "The flashlight is busy. Close the camera and try again."))
        }
    }

    private fun setVolume(call: MethodCall, r: MethodChannel.Result) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val direction = when (call.argument<String>("change")) {
            "up" -> AudioManager.ADJUST_RAISE
            "down" -> AudioManager.ADJUST_LOWER
            "mute" -> AudioManager.ADJUST_MUTE
            "unmute" -> AudioManager.ADJUST_UNMUTE
            else -> return r.success(result(false, "Say volume up, volume down, mute or unmute."))
        }
        am.adjustStreamVolume(AudioManager.STREAM_MUSIC, direction, AudioManager.FLAG_SHOW_UI)
        r.success(result(true))
    }

    private fun openSettings(call: MethodCall, r: MethodChannel.Result) {
        val action = when (call.argument<String>("screen")) {
            "wifi" -> Settings.ACTION_WIFI_SETTINGS
            "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
            "display" -> Settings.ACTION_DISPLAY_SETTINGS
            "sound" -> Settings.ACTION_SOUND_SETTINGS
            "battery" -> Intent.ACTION_POWER_USAGE_SUMMARY
            "apps" -> Settings.ACTION_APPLICATION_SETTINGS
            "location" -> Settings.ACTION_LOCATION_SOURCE_SETTINGS
            else -> Settings.ACTION_SETTINGS
        }
        r.success(if (start(Intent(action))) result(true) else result(false, "That settings screen could not be opened."))
    }

    // ------------------------------------------------------------------ controlling the phone (Accessibility)

    /** Is phone control part of this download? (The normal build leaves it out: Android's Play Protect blocks sideloaded apps that declare it.) */
    @Suppress("DEPRECATION")
    private fun controlIncluded(): Boolean = try {
        context.packageManager.getServiceInfo(ComponentName(context, EscanorControlService::class.java), 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    /**
     * Android 13+ greys out Accessibility for apps installed from a downloaded file ("Controlled by restricted setting") until the
     * person allows it in App info. True: restricted (or, where Android will not say, installed from a file and so probably
     * restricted). False: not restricted. Null: this Android does not say.
     */
    @Suppress("DEPRECATION")
    private fun controlRestricted(): Boolean? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
        val pkg = context.packageName
        try {
            val ops = context.getSystemService(AppOpsManager::class.java)
            val mode = ops.unsafeCheckOpNoThrow("android:access_restricted_settings", Process.myUid(), pkg)
            return mode == AppOpsManager.MODE_ERRORED || mode == AppOpsManager.MODE_IGNORED
        } catch (e: Exception) {
            // Newer Android lets only the system read that setting: go by how the app was installed instead.
        }
        try {
            val source = context.packageManager.getInstallSourceInfo(pkg).packageSource
            if (source == PackageInstaller.PACKAGE_SOURCE_DOWNLOADED_FILE || source == PackageInstaller.PACKAGE_SOURCE_LOCAL_FILE) return true
            if (source == PackageInstaller.PACKAGE_SOURCE_STORE) return false
        } catch (e: Exception) {
            // not known
        }
        return null
    }

    /** Has the person turned on Escanor in Accessibility settings, and is Android still holding that switch back? */
    private fun controlStatus(r: MethodChannel.Result) {
        r.success(hashMapOf("enabled" to EscanorControlService.isRunning(), "available" to controlIncluded(), "restricted" to controlRestricted()))
    }

    /**
     * Open Android's Accessibility settings, where the person switches Escanor on. Android allows nothing else: no app can do this
     * for them. Goes straight to Escanor's own switch where the phone supports it, else to the list.
     */
    private fun openControlSettings(r: MethodChannel.Result) {
        val direct = Intent("android.settings.ACCESSIBILITY_DETAILS_SETTINGS")
            .putExtra(Intent.EXTRA_COMPONENT_NAME, ComponentName(context, EscanorControlService::class.java).flattenToString())
        var opened = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && start(direct)
        if (!opened) opened = start(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        r.success(if (opened) result(true) else result(false, "Open Android Settings, then Accessibility, and turn on Escanor."))
    }

    /**
     * One thing done on the phone as a person would: {action: "global", name}, {action: "click", text}, {action: "scroll", direction},
     * {action: "type", text}, {action: "read"}. Says so plainly when the person has not turned the permission on.
     */
    private fun control(call: MethodCall, r: MethodChannel.Result) {
        val svc = EscanorControlService.get()
        if (svc == null && !controlIncluded()) {
            val out = result(false, "This download of Escanor does not include phone control. Get the “with phone control” APK from the release page.")
            out["needs"] = "controlBuild"
            return r.success(out)
        }
        if (svc == null) {
            val out = result(false, NEEDS_CONTROL)
            out["needs"] = "accessibility"
            return r.success(out)
        }
        val text = call.argument<String>("text") ?: ""
        r.success(
            when (call.argument<String>("action")) {
                "global" -> if (svc.global(call.argument<String>("name") ?: "")) result(true) else result(false, "This phone could not do that.")
                "click" -> if (svc.clickText(text)) result(true) else result(false, "I could not find “$text” on the screen.")
                "scroll" -> if (svc.scroll(call.argument<String>("direction") != "up")) result(true) else result(false, "There is nothing to scroll here.")
                "type" -> if (svc.typeText(text)) result(true) else result(false, "There is no text box on the screen to type into.")
                "read" -> {
                    val words = svc.readScreen(1200)
                    if (words.isEmpty()) result(false, "I could not read anything on this screen.") else result(true, words)
                }
                else -> result(false, "I do not know how to do that.")
            },
        )
    }

    // ------------------------------------------------------------------ "Hey Escanor"

    private fun wakeStatus(r: MethodChannel.Result) {
        r.success(
            hashMapOf(
                "running" to WakeWordService.isRunning(),
                "modelReady" to WakeWordService.modelReady(context),
                "downloading" to downloading,
                "micAllowed" to granted(Manifest.permission.RECORD_AUDIO),
                // what lets "Hey Escanor" open the app when it is not showing (see WakeAction)
                "opensDirectly" to WakeAction.opensDirectly(),
                "fullScreenDeclared" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || WakeAction.declares(context, Manifest.permission.USE_FULL_SCREEN_INTENT)),
                "fullScreenAllowed" to WakeAction.canFullScreen(context),
            ),
        )
    }

    private fun openSettingsPage(r: MethodChannel.Result, i: Intent) {
        try {
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(i)
            r.success(result(true))
        } catch (e: Exception) {
            r.success(result(false, "Android would not open that settings page. Open Settings, Apps, Escanor to find it."))
        }
    }

    private fun progress(pct: Int) {
        main.post { channel.invokeMethod("wakeModelProgress", hashMapOf("percent" to pct)) }
    }

    /** Download the small speech model (about 40 MB) once, over https, with progress events. */
    private fun wakeDownloadModel(r: MethodChannel.Result) {
        if (WakeWordService.modelReady(context)) return r.success(result(true))
        if (downloading) return r.success(result(false, "It is already downloading."))
        downloading = true
        Thread({
            val tmp = File(context.cacheDir, "wake-model.zip")
            try {
                val c = URL(MODEL_URL).openConnection() as HttpURLConnection
                c.connectTimeout = 15000
                c.readTimeout = 30000
                val total = c.contentLengthLong
                var got = 0L
                var lastPct = -1
                c.inputStream.use { input ->
                    FileOutputStream(tmp).use { out ->
                        val buf = ByteArray(64 * 1024)
                        while (true) {
                            val n = input.read(buf)
                            if (n <= 0) break
                            out.write(buf, 0, n)
                            got += n
                            val pct = if (total > 0) (got * 90 / total).toInt() else 0 // the last tenth is unpacking
                            if (pct != lastPct) {
                                lastPct = pct
                                progress(pct)
                            }
                        }
                    }
                }
                val dir = context.filesDir
                val root = dir.canonicalPath + File.separator
                ZipInputStream(FileInputStream(tmp)).use { zin ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val e = zin.nextEntry ?: break
                        val target = File(dir, e.name)
                        if (!target.canonicalPath.startsWith(root)) throw SecurityException("bad zip entry")
                        if (e.isDirectory) {
                            target.mkdirs()
                            continue
                        }
                        target.parentFile?.mkdirs()
                        FileOutputStream(target).use { out ->
                            while (true) {
                                val n = zin.read(buf)
                                if (n <= 0) break
                                out.write(buf, 0, n)
                            }
                        }
                    }
                }
                progress(100)
                reply(r, if (WakeWordService.modelReady(context)) result(true) else result(false, "The voice model did not unpack. Try again."))
            } catch (e: Exception) {
                reply(r, result(false, "Could not download the voice model. Check your connection and try again."))
            } finally {
                downloading = false
                tmp.delete()
            }
        }, "escanor-wake-download").start()
    }

    private fun wakeStart(r: MethodChannel.Result) {
        if (!WakeWordService.modelReady(context)) return r.success(result(false, "The voice model is not downloaded yet."))
        if (!granted(Manifest.permission.RECORD_AUDIO)) {
            return r.success(result(false, "Allow the microphone for Escanor first (Android Settings, Apps, Escanor, Permissions)."))
        }
        val i = Intent(context, WakeWordService::class.java)
        try {
            ContextCompat.startForegroundService(context, i)
            r.success(result(true))
        } catch (e: Exception) {
            r.success(result(false, "Android would not let Escanor listen in the background. Open the app and try again."))
        }
    }
}
