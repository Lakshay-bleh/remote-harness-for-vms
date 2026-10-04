package io.visey.remoteharness;

import android.app.NotificationManager;
import android.content.Context;
import android.os.Bundle;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    private static volatile boolean foreground = false;

    /** Whether the app is showing right now (the wake word opens voice mode itself then, and raises a notification otherwise). */
    static boolean isForeground() {
        return foreground;
    }

    @Override
    public void onCreate(Bundle savedInstanceState) {
        // The phone-side tools of the Escanor voice assistant (apps, calls, alarms, torch, volume, settings).
        registerPlugin(EscanorDevicePlugin.class);
        super.onCreate(savedInstanceState);
    }

    @Override
    public void onResume() {
        super.onResume();
        foreground = true;
        // "Hey! I'm listening" has done its job once the app is in front.
        ((NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE)).cancel(WakeAction.ID_HEARD);
    }

    @Override
    public void onPause() {
        foreground = false;
        super.onPause();
    }
}
