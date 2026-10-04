import { registerPlugin } from '@capacitor/core';
import type { PluginListenerHandle } from '@capacitor/core';
import { isNative } from '../../api';
import type { DevicePlugin, PluginResult } from './actions';
import type { WakeStatus } from './wakeWord';

/** What the native side offers beyond the assistant's phone tools: "Hey Escanor" (see WakeWordService.java). */
interface WakeNative {
  wakeStatus(): Promise<WakeStatus>;
  wakeDownloadModel(): Promise<PluginResult>;
  wakeStart(): Promise<PluginResult>;
  wakeStop(): Promise<PluginResult>;
  wakePause(o: { paused: boolean }): Promise<PluginResult>;
  wakeDeleteModel(): Promise<PluginResult>;
  addListener(event: 'wake', cb: () => void): Promise<PluginListenerHandle>;
  addListener(event: 'wakeModelProgress', cb: (e: { percent: number }) => void): Promise<PluginListenerHandle>;
}

/** The Android side of the assistant (EscanorDevicePlugin.java): apps, calls, alarms, torch, volume, settings, phone control, wake word. */
export const Device = registerPlugin<DevicePlugin & WakeNative>('EscanorDevice');

/** The phone's tools, or null where there is no phone (the app in a browser). */
export const deviceOrNull = (): DevicePlugin | null => (isNative() ? Device : null);
