import { defineConfig } from 'vitest/config';

// Shared test configuration for the scupper-lock workspace. Both the agent's
// local `npx vitest run` and the task verifier use this file.
export default defineConfig({
  esbuild: { jsx: 'automatic' },
  test: {
    environment: 'jsdom',
    globals: true,
    include: ['visible/**/*.test.tsx', '.hidden-tests/**/*.test.tsx'],
    setupFiles: ['./vitest.setup.ts'],
    testTimeout: 15000,
    hookTimeout: 30000,
    fileParallelism: false,
    pool: 'forks',
    poolOptions: { forks: { singleFork: true } },
  },
});