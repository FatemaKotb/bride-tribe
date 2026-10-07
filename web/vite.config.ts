import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';
import { VitePWA } from 'vite-plugin-pwa';

const THEME_COLOR = '#228be6'; // Mantine's default primary color

// https://vite.dev/config/
export default defineConfig({
  // Relative paths, so the build works at any address, such as a GitHub
  // Pages project site. HashRouter keeps every route on index.html.
  base: './',
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['apple-touch-icon-180x180.png'],
      manifest: {
        name: 'Bride Tribe',
        short_name: 'Bride Tribe',
        description: 'Items, cars, and statuses for the bridal party on the wedding day.',
        theme_color: THEME_COLOR,
        background_color: '#ffffff',
        display: 'standalone',
        start_url: '.',
        scope: '.',
        icons: [
          { src: 'pwa-192x192.png', sizes: '192x192', type: 'image/png' },
          { src: 'pwa-512x512.png', sizes: '512x512', type: 'image/png' },
          { src: 'maskable-icon-512x512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      // Cache the app shell so it opens on a weak signal. Data calls always
      // go to the network.
      workbox: {
        globPatterns: ['**/*.{js,css,html,png,svg,webmanifest}'],
        navigateFallback: 'index.html',
      },
    }),
  ],
});
