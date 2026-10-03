import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'io.visey.remoteharness',
  appName: 'Escanor',
  webDir: 'dist',
  backgroundColor: '#050505',
  server: {
    // The app is served from https. Hubs and the Escanor API must be https/wss too: the app refuses anything else (see api.ts and
    // settings/apiUrl.ts), so the hub token and every message travel encrypted.
    androidScheme: 'https',
    cleartext: false,
  },
  android: {
    // The one exception is a computer on the person's own Wi-Fi, reached over plain http/ws with every message sealed end to end.
    // That is a mixed-content request from an https page, which Android blocks unless this is on. The app only opens such addresses
    // for private/local hosts (isLocalAddress), never for the internet.
    allowMixedContent: true,
  },
};

export default config;
