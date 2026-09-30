import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

const HUB_URL = process.env.HUB_DEV_URL || 'http://localhost:8787';

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['icon-192.png'],
      manifest: {
        name: 'Escanor',
        short_name: 'Escanor',
        description: 'Chat with an AI that works on your accounts and code, on its own private machine.',
        theme_color: '#faf9f5',
        background_color: '#faf9f5',
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
