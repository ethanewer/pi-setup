import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/react';
import App from '../src/App.jsx';
import home from '../src/data/home.mjs';

describe('app smoke', () => {
  it('renders the default (home) page and shows key content', () => {
    const { container } = render(<App />);
    expect(container.querySelector('main#main-content')).not.toBeNull();
    expect(container.querySelector('.brand-name').textContent).toContain('Lanternwell');
    expect(container.querySelectorAll('.service-card').length).toBeGreaterThanOrEqual(2);
  });
});
