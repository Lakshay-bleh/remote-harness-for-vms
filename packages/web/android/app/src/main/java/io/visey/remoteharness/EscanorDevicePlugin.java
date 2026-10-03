package io.visey.remoteharness;

import android.Manifest;
import android.content.Context;
import android.content.Intent;
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


import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/**
 * What the Escanor voice assistant can do on this phone: open any installed app, open a link, dial, set alarms and timers, the
 * torch, the volume and the system settings screens.
 *
 * Deliberately only things that are safe to get wrong. Dialing OPENS THE DIALER with the number filled in (it never places the
 * call by itself, so a misheard word cannot ring anyone), and the contacts are read only when the person asks to call someone by
 * name, behind Android's own permission prompt.
 */
@CapacitorPlugin(
    name = "EscanorDevice",
    permissions = { @Permission(strings = { Manifest.permission.READ_CONTACTS }, alias = "contacts") }
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
        call.resolve(start(new Intent(Intent.ACTION_DIAL, Uri.parse("tel:" + Uri.encode(numbers.get(0))))) ? result(true, labels.get(0)) : result(false, "This phone cannot make calls."));
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
}
