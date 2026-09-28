import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

const HUB_URL = process.env.HUB_DEV_URL || 'http://localhost:8787';

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['icon-mask.svg'],
      manifest: {
        name: 'Remote Harness',
        short_name: 'Harness',
        description: 'Chat with and control your Claude Code sessions running on any VM.',
        theme_color: '#0b0f14',
        background_color: '#0b0f14',
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
