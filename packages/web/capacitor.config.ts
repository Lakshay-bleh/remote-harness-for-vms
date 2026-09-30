import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'io.visey.remoteharness',
  appName: 'Escanor',
  webDir: 'dist',
  backgroundColor: '#050505',
  server: {
    // http scheme + cleartext so the app can talk to either an http:// or https:// hub
    // without the webview blocking it as mixed content.
    androidScheme: 'http',
    cleartext: true,
  },
};

export default config;
