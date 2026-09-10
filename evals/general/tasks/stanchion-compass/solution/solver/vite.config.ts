import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// stanchion-compass: route-level code splitting (lazy views) plus an explicit
// manualChunks rule so third-party vendor code (react, react-dom, ...) lands
// in its own chunk instead of the entry. The heavy route data modules stay in
// their per-view lazy chunks.
export default defineConfig({
  plugins: [react()],
  build: {
    target: 'es2020',
    sourcemap: false,
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('node_modules')) {
            return 'vendor';
          }
        },
      },
    },
  },
});