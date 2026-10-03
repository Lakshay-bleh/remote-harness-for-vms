package io.visey.remoteharness;

import android.os.Bundle;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        // The phone-side tools of the Escanor voice assistant (apps, calls, alarms, torch, volume, settings).
        registerPlugin(EscanorDevicePlugin.class);
        super.onCreate(savedInstanceState);
    }
}
