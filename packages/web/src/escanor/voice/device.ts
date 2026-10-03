import { registerPlugin } from '@capacitor/core';
import { isNative } from '../../api';
import type { DevicePlugin } from './actions';

/** The Android side of the assistant (EscanorDevicePlugin.java): apps, calls, alarms, torch, volume, settings. */
const Device = registerPlugin<DevicePlugin>('EscanorDevice');

/** The phone's tools, or null where there is no phone (the app in a browser). */
export const deviceOrNull = (): DevicePlugin | null => (isNative() ? Device : null);
