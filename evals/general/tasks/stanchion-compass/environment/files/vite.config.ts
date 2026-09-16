import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// stanchion-compass build config as shipped: the app builds and works, but
// every route view and all heavy data modules bundle into the single entry
// chunk. The task is to fix the initial payload (see instruction.md).
export default defineConfig({
  plugins: [react()],
  build: {
    target: 'es2020',
    sourcemap: false,
  },
});