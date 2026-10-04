package io.visey.remoteharness;

import android.Manifest;
import android.app.AppOpsManager;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInstaller;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.database.Cursor;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.media.AudioManager;
import android.net.Uri;
import android.provider.AlarmClock;
import android.provider.ContactsContract;
import android.provider.Settings;

import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;
import com.getcapacitor.PermissionState;


import android.os.Build;
import android.os.Process;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/**
 * What the Escanor voice assistant can do on this phone: open any installed app, open a link, dial, set alarms and timers, the
 * torch, the volume and the system settings screens.
 *
 * Dialing opens the dialer with the number filled in unless the person has turned on "call directly" (and allowed Android's call
 * permission), in which case the call is placed. The contacts are read only when the person asks to call someone by name, behind
 * Android's own permission prompt. Controlling the phone (home, back, scroll, tap, type) works only while the person has switched
 * Escanor on in Accessibility settings (EscanorControlService).
 */
@CapacitorPlugin(
    name = "EscanorDevice",
    permissions = {
        @Permission(strings = { Manifest.permission.READ_CONTACTS }, alias = "contacts"),
        @Permission(strings = { Manifest.permission.CALL_PHONE }, alias = "call")
    }
)
public class EscanorDevicePlugin extends Plugin {

    private static JSObject result(boolean ok, String message) {
        JSObject o = new JSObject();
        o.put("ok", ok);
        if (message != null) o.put("message", message);
        return o;
    }

    private boolean start(Intent intent) {
        try {
            getActivity().startActivity(intent);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    // ------------------------------------------------------------------ apps

    /** Every app with a launcher icon: its label and package. Matching a spoken name to one is done in the web layer (tested there). */
    @PluginMethod
    public void listApps(PluginCall call) {
        PackageManager pm = getContext().getPackageManager();
        Intent main = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
        List<ResolveInfo> found = pm.queryIntentActivities(main, 0);
        List<JSObject> apps = new ArrayList<>();
        for (ResolveInfo r : found) {
            JSObject a = new JSObject();
            a.put("label", String.valueOf(r.loadLabel(pm)));
            a.put("package", r.activityInfo.packageName);
            apps.add(a);
        }
        Collections.sort(apps, new Comparator<JSObject>() {
            @Override
            public int compare(JSObject x, JSObject y) {
                return x.getString("label", "").compareToIgnoreCase(y.getString("label", ""));
            }
        });
        JSObject out = new JSObject();
        out.put("apps", new JSArray(apps));
        call.resolve(out);
    }

    @PluginMethod
    public void launchPackage(PluginCall call) {
        String pkg = call.getString("package");
        if (pkg == null || pkg.isEmpty()) {
            call.resolve(result(false, "No app given."));
            return;
        }
        Intent intent = getContext().getPackageManager().getLaunchIntentForPackage(pkg);
        call.resolve(intent != null && start(intent) ? result(true, null) : result(false, "That app could not be opened."));
    }

    /** Open a web link in whatever app handles it (a youtube.com link opens the YouTube app if it is installed). https only. */
    @PluginMethod
    public void openUrl(PluginCall call) {
        String url = call.getString("url", "");
        if (url == null || !url.startsWith("https://")) {
            call.resolve(result(false, "Only https links can be opened."));
            return;
        }
        call.resolve(start(new Intent(Intent.ACTION_VIEW, Uri.parse(url))) ? result(true, null) : result(false, "Nothing on this phone can open that link."));
    }

    // ------------------------------------------------------------------ calls

    private boolean callAllowed() {
        return getPermissionState("call") == PermissionState.GRANTED;
    }

    /** Ring the number if the call permission is there and `direct` was asked for; otherwise open the dialer with it filled in. */
    private JSObject placeOrDial(String number, boolean direct, String label) {
        Intent intent = direct && callAllowed() ? new Intent(Intent.ACTION_CALL, Uri.parse("tel:" + Uri.encode(number))) : new Intent(Intent.ACTION_DIAL, Uri.parse("tel:" + Uri.encode(number)));
        boolean rang = direct && callAllowed();
        if (!start(intent)) return result(false, "This phone cannot make calls.");
        JSObject out = result(true, label);
        out.put("direct", rang);
        return out;
    }

    /** Is Android's call permission granted? (So the settings page can show whether "call directly" will really ring.) */
    @PluginMethod
    public void callStatus(PluginCall call) {
        JSObject out = new JSObject();
        out.put("granted", callAllowed());
        call.resolve(out);
    }

    @PluginMethod
    public void requestCallPermission(PluginCall call) {
        if (callAllowed()) {
            call.resolve(result(true, null));
            return;
        }
        requestPermissionForAlias("call", call, "callPermissionResult");
    }

    @PermissionCallback
    private void callPermissionResult(PluginCall call) {
        call.resolve(callAllowed() ? result(true, null) : result(false, "Calling directly needs the Phone permission. In Android Settings, open Apps, Escanor, Permissions, and allow Phone."));
    }

    /** A number, called directly when asked to and allowed (else the dialer). */
    @PluginMethod
    public void callNumber(PluginCall call) {
        String number = call.getString("number", "");
        if (number == null || !number.matches("\\+?[0-9]{3,20}")) {
            call.resolve(result(false, "That is not a phone number."));
            return;
        }
        boolean direct = Boolean.TRUE.equals(call.getBoolean("direct", false));
        if (direct && !callAllowed()) {
            requestPermissionForAlias("call", call, "callNumberPermission");
            return;
        }
        call.resolve(placeOrDial(number, direct, null));
    }

    @PermissionCallback
    private void callNumberPermission(PluginCall call) {
        // allowed: ring; refused: open the dialer instead, and say why it did not ring
        String number = call.getString("number", "");
        JSObject out = placeOrDial(number, true, null);
        if (!callAllowed() && out.getBoolean("ok", false)) out.put("message", "I opened the dialer: calling directly needs the Phone permission.");
        call.resolve(out);
    }

    /** Opens the dialer with the number typed in. The person presses call; a misheard word never rings anyone. */
    @PluginMethod
    public void dial(PluginCall call) {
        String number = call.getString("number", "");
        if (number == null || !number.matches("\\+?[0-9]{3,20}")) {
            call.resolve(result(false, "That is not a phone number."));
            return;
        }
        call.resolve(start(new Intent(Intent.ACTION_DIAL, Uri.parse("tel:" + number))) ? result(true, null) : result(false, "This phone cannot make calls."));
    }

    /** Find a contact by name (asks Android for permission the first time) and open the dialer on their number. */
    @PluginMethod
    public void callContact(PluginCall call) {
        if (getPermissionState("contacts") != PermissionState.GRANTED) {
            requestPermissionForAlias("contacts", call, "contactsPermission");
            return;
        }
        findAndDial(call);
    }

    @PermissionCallback
    private void contactsPermission(PluginCall call) {
        if (getPermissionState("contacts") == PermissionState.GRANTED) findAndDial(call);
        else call.resolve(result(false, "Allow Escanor to read your contacts, or say the number."));
    }

    /** Every contact with a phone number: name and numbers (mobile first). The matching of a spoken name to one is done in the web layer, on this phone. */
    @PluginMethod
    public void listContacts(PluginCall call) {
        if (getPermissionState("contacts") != PermissionState.GRANTED) {
            requestPermissionForAlias("contacts", call, "listContactsPermission");
            return;
        }
        readContacts(call);
    }

    @PermissionCallback
    private void listContactsPermission(PluginCall call) {
        if (getPermissionState("contacts") == PermissionState.GRANTED) readContacts(call);
        else call.resolve(result(false, "Allow Escanor to read your contacts so it can find who to call."));
    }

    private void readContacts(PluginCall call) {
        java.util.LinkedHashMap<String, List<String>> byName = new java.util.LinkedHashMap<>();
        try (Cursor c = getContext().getContentResolver().query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            new String[] { ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER, ContactsContract.CommonDataKinds.Phone.TYPE },
            null, null, ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC"
        )) {
            while (c != null && c.moveToNext() && byName.size() < 5000) {
                String name = c.getString(0);
                String number = c.getString(1);
                if (name == null || number == null) continue;
                List<String> numbers = byName.get(name);
                if (numbers == null) {
                    numbers = new ArrayList<>();
                    byName.put(name, numbers);
                }
                String digits = number.replaceAll("[^0-9+]", "");
                if (digits.length() >= 3 && !numbers.contains(digits)) {
                    if (c.getInt(2) == ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE) numbers.add(0, digits);
                    else numbers.add(digits);
                }
            }
        } catch (SecurityException e) {
            call.resolve(result(false, "Escanor is not allowed to read your contacts."));
            return;
        }
        List<JSObject> list = new ArrayList<>();
        for (java.util.Map.Entry<String, List<String>> e : byName.entrySet()) {
            if (e.getValue().isEmpty()) continue;
            JSObject o = new JSObject();
            o.put("name", e.getKey());
            o.put("numbers", new JSArray(e.getValue()));
            list.add(o);
        }
        JSObject out = result(true, null);
        out.put("contacts", new JSArray(list));
        call.resolve(out);
    }

    private void findAndDial(PluginCall call) {
        String name = call.getString("name", "");
        if (name == null || name.trim().isEmpty()) {
            call.resolve(result(false, "Who should I call?"));
            return;
        }
        List<String> labels = new ArrayList<>();
        List<String> numbers = new ArrayList<>();
        try (Cursor c = getContext().getContentResolver().query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            new String[] { ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER },
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " LIKE ?",
            new String[] { "%" + name.trim() + "%" },
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC"
        )) {
            while (c != null && c.moveToNext() && labels.size() < 5) {
                String number = c.getString(1);
                if (number != null && !numbers.contains(number)) {
                    labels.add(c.getString(0));
                    numbers.add(number);
                }
            }
        } catch (SecurityException e) {
            call.resolve(result(false, "Escanor is not allowed to read your contacts."));
            return;
        }
        if (numbers.isEmpty()) {
            call.resolve(result(false, "I could not find " + name + " in your contacts."));
            return;
        }
        if (numbers.size() > 1) {
            // More than one match: do not guess whom to ring. The web layer says who it found.
            JSObject out = result(false, "I found more than one: " + String.join(", ", labels) + ". Say the full name.");
            call.resolve(out);
            return;
        }
        boolean direct = Boolean.TRUE.equals(call.getBoolean("direct", false)) && callAllowed();
        call.resolve(placeOrDial(numbers.get(0), direct, labels.get(0)));
    }

    // ------------------------------------------------------------------ clock

    @PluginMethod
    public void setAlarm(PluginCall call) {
        Integer hour = call.getInt("hour");
        Integer minute = call.getInt("minute");
        if (hour == null || minute == null || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
            call.resolve(result(false, "That is not a time."));
            return;
        }
        Intent i = new Intent(AlarmClock.ACTION_SET_ALARM)
            .putExtra(AlarmClock.EXTRA_HOUR, hour)
            .putExtra(AlarmClock.EXTRA_MINUTES, minute)
            .putExtra(AlarmClock.EXTRA_MESSAGE, "Escanor")
            .putExtra(AlarmClock.EXTRA_SKIP_UI, true);
        call.resolve(start(i) ? result(true, null) : result(false, "No clock app could set that alarm."));
    }

    @PluginMethod
    public void setTimer(PluginCall call) {
        Integer seconds = call.getInt("seconds");
        if (seconds == null || seconds < 1 || seconds > 86400) {
            call.resolve(result(false, "That is not a length of time."));
            return;
        }
        Intent i = new Intent(AlarmClock.ACTION_SET_TIMER).putExtra(AlarmClock.EXTRA_LENGTH, seconds).putExtra(AlarmClock.EXTRA_SKIP_UI, true);
        call.resolve(start(i) ? result(true, null) : result(false, "No clock app could start that timer."));
    }

    // ------------------------------------------------------------------ hardware

    @PluginMethod
    public void setTorch(PluginCall call) {
        boolean on = Boolean.TRUE.equals(call.getBoolean("on", false));
        CameraManager cm = (CameraManager) getContext().getSystemService(Context.CAMERA_SERVICE);
        try {
            for (String id : cm.getCameraIdList()) {
                CameraCharacteristics ch = cm.getCameraCharacteristics(id);
                Boolean flash = ch.get(CameraCharacteristics.FLASH_INFO_AVAILABLE);
                Integer facing = ch.get(CameraCharacteristics.LENS_FACING);
                if (Boolean.TRUE.equals(flash) && facing != null && facing == CameraCharacteristics.LENS_FACING_BACK) {
                    cm.setTorchMode(id, on);
                    call.resolve(result(true, null));
                    return;
                }
            }
            call.resolve(result(false, "This phone has no flashlight."));
        } catch (CameraAccessException | IllegalArgumentException e) {
            call.resolve(result(false, "The flashlight is busy. Close the camera and try again."));
        }
    }

    @PluginMethod
    public void setVolume(PluginCall call) {
        String change = call.getString("change", "");
        AudioManager am = (AudioManager) getContext().getSystemService(Context.AUDIO_SERVICE);
        int direction;
        if ("up".equals(change)) direction = AudioManager.ADJUST_RAISE;
        else if ("down".equals(change)) direction = AudioManager.ADJUST_LOWER;
        else if ("mute".equals(change)) direction = AudioManager.ADJUST_MUTE;
        else if ("unmute".equals(change)) direction = AudioManager.ADJUST_UNMUTE;
        else {
            call.resolve(result(false, "Say volume up, volume down, mute or unmute."));
            return;
        }
        am.adjustStreamVolume(AudioManager.STREAM_MUSIC, direction, AudioManager.FLAG_SHOW_UI);
        call.resolve(result(true, null));
    }

    @PluginMethod
    public void openSettings(PluginCall call) {
        String screen = call.getString("screen", "");
        String action;
        if ("wifi".equals(screen)) action = Settings.ACTION_WIFI_SETTINGS;
        else if ("bluetooth".equals(screen)) action = Settings.ACTION_BLUETOOTH_SETTINGS;
        else if ("display".equals(screen)) action = Settings.ACTION_DISPLAY_SETTINGS;
        else if ("sound".equals(screen)) action = Settings.ACTION_SOUND_SETTINGS;
        else if ("battery".equals(screen)) action = Intent.ACTION_POWER_USAGE_SUMMARY;
        else if ("apps".equals(screen)) action = Settings.ACTION_APPLICATION_SETTINGS;
        else if ("location".equals(screen)) action = Settings.ACTION_LOCATION_SOURCE_SETTINGS;
        else action = Settings.ACTION_SETTINGS;
        call.resolve(start(new Intent(action)) ? result(true, null) : result(false, "That settings screen could not be opened."));
    }

    // ------------------------------------------------------------------ controlling the phone (Accessibility)

    private static final String NEEDS_CONTROL = "Controlling your phone needs Escanor turned on in Accessibility settings.";

    /** Is phone control part of this download? (The normal build leaves it out: Android's Play Protect blocks sideloaded apps that declare it.) */
    private boolean controlIncluded() {
        try {
            getContext().getPackageManager().getServiceInfo(new android.content.ComponentName(getContext(), EscanorControlService.class), 0);
            return true;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }

    /**
     * Android 13+ greys out Accessibility for apps installed from a downloaded file ("Controlled by restricted setting") until the
     * person allows it in App info. True: restricted (or, where Android will not say, installed from a file and so probably
     * restricted). False: not restricted. Null: this Android does not say.
     */
    private Boolean controlRestricted() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false;
        String pkg = getContext().getPackageName();
        try {
            AppOpsManager ops = getContext().getSystemService(AppOpsManager.class);
            int mode = ops.unsafeCheckOpNoThrow("android:access_restricted_settings", Process.myUid(), pkg);
            return mode == AppOpsManager.MODE_ERRORED || mode == AppOpsManager.MODE_IGNORED;
        } catch (Exception e) {
            // Newer Android lets only the system read that setting: go by how the app was installed instead.
        }
        try {
            int source = getContext().getPackageManager().getInstallSourceInfo(pkg).getPackageSource();
            if (source == PackageInstaller.PACKAGE_SOURCE_DOWNLOADED_FILE || source == PackageInstaller.PACKAGE_SOURCE_LOCAL_FILE) return true;
            if (source == PackageInstaller.PACKAGE_SOURCE_STORE) return false;
        } catch (Exception e) {
            // not known
        }
        return null;
    }

    /** Has the person turned on Escanor in Accessibility settings, and is Android still holding that switch back? */
    @PluginMethod
    public void controlStatus(PluginCall call) {
        JSObject out = new JSObject();
        out.put("enabled", EscanorControlService.isRunning());
        out.put("available", controlIncluded());
        Boolean restricted = controlRestricted();
        out.put("restricted", restricted == null ? JSObject.NULL : restricted);
        call.resolve(out);
    }

    /**
     * Open Android's Accessibility settings, where the person switches Escanor on. Android allows nothing else: no app can do this
     * for them. Goes straight to Escanor's own switch where the phone supports it, else to the list.
     */
    @PluginMethod
    public void openControlSettings(PluginCall call) {
        Intent direct = new Intent("android.settings.ACCESSIBILITY_DETAILS_SETTINGS")
            .putExtra(Intent.EXTRA_COMPONENT_NAME, new android.content.ComponentName(getContext(), EscanorControlService.class).flattenToString());
        boolean opened = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && start(direct);
        if (!opened) opened = start(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS));
        call.resolve(opened ? result(true, null) : result(false, "Open Android Settings, then Accessibility, and turn on Escanor."));
    }

    /** Open Escanor's App info, where the ⋮ menu has "Allow restricted settings" (Android 13+, for apps installed from a file). */
    @PluginMethod
    public void openAppInfo(PluginCall call) {
        Intent info = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", getContext().getPackageName(), null));
        call.resolve(start(info) ? result(true, null) : result(false, "Open Android Settings, then Apps, then Escanor."));
    }

    /**
     * One thing done on the phone as a person would: {action: "global", name}, {action: "click", text}, {action: "scroll", direction},
     * {action: "type", text}, {action: "read"}. Says so plainly when the person has not turned the permission on.
     */
    @PluginMethod
    public void control(PluginCall call) {
        EscanorControlService svc = EscanorControlService.get();
        if (svc == null && !controlIncluded()) {
            JSObject out = result(false, "This download of Escanor does not include phone control. Get the “with phone control” APK from the release page.");
            out.put("needs", "controlBuild");
            call.resolve(out);
            return;
        }
        if (svc == null) {
            JSObject out = result(false, NEEDS_CONTROL);
            out.put("needs", "accessibility");
            call.resolve(out);
            return;
        }
        String action = call.getString("action", "");
        boolean ok;
        switch (action == null ? "" : action) {
            case "global":
                ok = svc.global(call.getString("name", ""));
                call.resolve(ok ? result(true, null) : result(false, "This phone could not do that."));
                return;
            case "click":
                ok = svc.clickText(call.getString("text", ""));
                call.resolve(ok ? result(true, null) : result(false, "I could not find “" + call.getString("text", "") + "” on the screen."));
                return;
            case "scroll":
                ok = svc.scroll(!"up".equals(call.getString("direction", "down")));
                call.resolve(ok ? result(true, null) : result(false, "There is nothing to scroll here."));
                return;
            case "type":
                ok = svc.typeText(call.getString("text", ""));
                call.resolve(ok ? result(true, null) : result(false, "There is no text box on the screen to type into."));
                return;
            case "read": {
                String words = svc.readScreen(1200);
                call.resolve(words.isEmpty() ? result(false, "I could not read anything on this screen.") : result(true, words));
                return;
            }
            default:
                call.resolve(result(false, "I do not know how to do that."));
        }
    }

    // ------------------------------------------------------------------ "Hey Escanor"

    private static volatile EscanorDevicePlugin live;
    private static volatile boolean downloading = false;
    private static final String MODEL_URL = "https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip";

    @Override
    public void load() {
        live = this;
    }

    @Override
    protected void handleOnDestroy() {
        if (live == this) live = null;
    }

    /** Tell the app, if it is open and showing, that the phrase was heard. False when nothing is there to hear it (the service then raises a notification). */
    static boolean notifyWake() {
        EscanorDevicePlugin p = live;
        if (p == null || !p.hasListeners("wake") || p.getActivity() == null || !p.getActivity().hasWindowFocus()) return false;
        p.notifyListeners("wake", new JSObject(), true);
        return true;
    }

    @PluginMethod
    public void wakeStatus(PluginCall call) {
        JSObject out = new JSObject();
        out.put("running", WakeWordService.isRunning());
        out.put("modelReady", WakeWordService.modelReady(getContext()));
        out.put("downloading", downloading);
        out.put("micAllowed", getContext().checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED);
        // what lets "Hey Escanor" open the app when it is not showing (see WakeAction)
        out.put("overlayAllowed", WakeAction.canOverlay(getContext()));
        out.put("fullScreenAllowed", WakeAction.canFullScreen(getContext()));
        call.resolve(out);
    }

    /** Android's "Display over other apps" page for Escanor. */
    @PluginMethod
    public void wakeOpenOverlaySettings(PluginCall call) {
        openSettings(call, new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:" + getContext().getPackageName())));
    }

    /** Android 14+: "Full-screen notifications" for Escanor (the page that lets a notification take over the screen). */
    @PluginMethod
    public void wakeOpenFullScreenSettings(PluginCall call) {
        if (Build.VERSION.SDK_INT < 34) {
            call.resolve(result(true, null));
            return;
        }
        openSettings(call, new Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:" + getContext().getPackageName())));
    }

    private void openSettings(PluginCall call, Intent i) {
        try {
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            getContext().startActivity(i);
            call.resolve(result(true, null));
        } catch (Exception e) {
            call.resolve(result(false, "Android would not open that settings page. Open Settings, Apps, Escanor to find it."));
        }
    }

    /** Act as though "Hey Escanor" was heard in a few seconds, so the person can press Home and see what happens. */
    @PluginMethod
    public void wakeTest(PluginCall call) {
        final Context ctx = getContext().getApplicationContext();
        new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(() -> WakeAction.fire(ctx), 6000);
        call.resolve(result(true, null));
    }

    /** Download the small speech model (about 40 MB) once, over https, with progress events. */
    @PluginMethod
    public void wakeDownloadModel(final PluginCall call) {
        if (WakeWordService.modelReady(getContext())) {
            call.resolve(result(true, null));
            return;
        }
        if (downloading) {
            call.resolve(result(false, "It is already downloading."));
            return;
        }
        downloading = true;
        final Context ctx = getContext().getApplicationContext();
        new Thread(new Runnable() {
            @Override
            public void run() {
                File tmp = new File(ctx.getCacheDir(), "wake-model.zip");
                try {
                    HttpURLConnection c = (HttpURLConnection) new URL(MODEL_URL).openConnection();
                    c.setConnectTimeout(15000);
                    c.setReadTimeout(30000);
                    long total = c.getContentLengthLong();
                    long got = 0;
                    int lastPct = -1;
                    try (InputStream in = c.getInputStream(); FileOutputStream out = new FileOutputStream(tmp)) {
                        byte[] buf = new byte[64 * 1024];
                        int n;
                        while ((n = in.read(buf)) > 0) {
                            out.write(buf, 0, n);
                            got += n;
                            int pct = total > 0 ? (int) (got * 90 / total) : 0; // the last tenth is unpacking
                            if (pct != lastPct) {
                                lastPct = pct;
                                JSObject p = new JSObject();
                                p.put("percent", pct);
                                notifyListeners("wakeModelProgress", p);
                            }
                        }
                    }
                    File dir = ctx.getFilesDir();
                    String root = dir.getCanonicalPath() + File.separator;
                    try (ZipInputStream zin = new ZipInputStream(new java.io.FileInputStream(tmp))) {
                        ZipEntry e;
                        byte[] buf = new byte[64 * 1024];
                        while ((e = zin.getNextEntry()) != null) {
                            File target = new File(dir, e.getName());
                            if (!target.getCanonicalPath().startsWith(root)) throw new SecurityException("bad zip entry");
                            if (e.isDirectory()) {
                                target.mkdirs();
                                continue;
                            }
                            target.getParentFile().mkdirs();
                            try (FileOutputStream out = new FileOutputStream(target)) {
                                int n;
                                while ((n = zin.read(buf)) > 0) out.write(buf, 0, n);
                            }
                        }
                    }
                    JSObject p = new JSObject();
                    p.put("percent", 100);
                    notifyListeners("wakeModelProgress", p);
                    call.resolve(WakeWordService.modelReady(ctx) ? result(true, null) : result(false, "The voice model did not unpack. Try again."));
                } catch (Exception e) {
                    call.resolve(result(false, "Could not download the voice model. Check your connection and try again."));
                } finally {
                    downloading = false;
                    tmp.delete();
                }
            }
        }, "escanor-wake-download").start();
    }

    @PluginMethod
    public void wakeStart(PluginCall call) {
        if (!WakeWordService.modelReady(getContext())) {
            call.resolve(result(false, "The voice model is not downloaded yet."));
            return;
        }
        if (getContext().checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            call.resolve(result(false, "Allow the microphone for Escanor first (Android Settings, Apps, Escanor, Permissions)."));
            return;
        }
        Intent i = new Intent(getContext(), WakeWordService.class);
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) getContext().startForegroundService(i);
            else getContext().startService(i);
            call.resolve(result(true, null));
        } catch (Exception e) {
            call.resolve(result(false, "Android would not let Escanor listen in the background. Open the app and try again."));
        }
    }

    @PluginMethod
    public void wakeStop(PluginCall call) {
        getContext().stopService(new Intent(getContext(), WakeWordService.class));
        call.resolve(result(true, null));
    }

    /** Voice mode is using the microphone: stop listening for the phrase until it is done. */
    @PluginMethod
    public void wakePause(PluginCall call) {
        WakeWordService.pause(Boolean.TRUE.equals(call.getBoolean("paused", true)));
        call.resolve(result(true, null));
    }

    @PluginMethod
    public void wakeDeleteModel(PluginCall call) {
        getContext().stopService(new Intent(getContext(), WakeWordService.class));
        File dir = WakeWordService.modelDir(getContext());
        deleteTree(dir);
        call.resolve(result(true, null));
    }

    private static void deleteTree(File f) {
        File[] kids = f.listFiles();
        if (kids != null) for (File k : kids) deleteTree(k);
        f.delete();
    }
}
