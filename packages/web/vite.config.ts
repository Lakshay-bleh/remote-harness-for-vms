import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { readFileSync } from 'node:fs';
import { VitePWA } from 'vite-plugin-pwa';

const pkg = JSON.parse(readFileSync(new URL('./package.json', import.meta.url), 'utf8')) as { version: string };

const HUB_URL = process.env.HUB_DEV_URL || 'http://localhost:8787';

export default defineConfig({
  // The release build stamps the same version into the APK (RH_VERSION_NAME); Settings shows it.
  define: { __APP_VERSION__: JSON.stringify(process.env.RH_VERSION_NAME || pkg.version) },
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['icon-mask.svg'],
      manifest: {
        name: 'Escanor',
        short_name: 'Escanor',
        description: 'Chat with an AI that works on your accounts and code, on its own private machine.',
        theme_color: '#050505',
        background_color: '#050505',
        display: 'standalone',
        orientation: 'portrait',
        icons: [
          { src: '/icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: '/icon-512.png', sizes: '512x512', type: 'image/png' },
          { src: '/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        navigateFallbackDenylist: [/^\/api/, /^\/ws/, /^\/agent/],
        // /auth/callback must reach the app (it carries the sign-in code), never a cached page.
      },
    }),
  ],
  server: {
    proxy: {
      '/api': { target: HUB_URL, changeOrigin: true },
      '/ws': { target: HUB_URL, ws: true, changeOrigin: true },
    },
  },
});
