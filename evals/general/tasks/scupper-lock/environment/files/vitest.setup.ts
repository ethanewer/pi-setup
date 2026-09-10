import { afterEach } from 'vitest';
import { cleanup } from '@testing-library/react';

// Guarantee a clean document between tests regardless of how the pool shares
// the jsdom environment.
afterEach(() => {
  cleanup();
});