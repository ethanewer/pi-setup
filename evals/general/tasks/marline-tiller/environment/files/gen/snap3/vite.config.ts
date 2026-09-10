import { defineConfig } from 'vite';

export default defineConfig({
  build: {
    lib: {
      entry: 'src/index.ts',
      name: 'marline-lib',
      formats: ['cjs'],
      fileName: (format: string) => `marline-lib.${format === 'es' ? 'mjs' : 'cjs'}`,
    },
    target: 'es2020',
    sourcemap: false,
    rollupOptions: {
      external: ['react', 'react-dom', 'react/jsx-runtime'],
    },
  },
});
