import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/react';
import App from '../../src/App.jsx';
import page from './page.mjs';
import {
  prepareDocument,
  collectAxeViolations,
  targetedFailures,
  FAILING_IMPACTS,
} from '../_support/a11y.mjs';

describe('a11y: team-directory page (hidden case)', () => {
  it('has no moderate+ axe violations and passes targeted checks', async () => {
    prepareDocument('Meet the care team — Lanternwell Clinic');
    render(<App page={page} />);
    const violations = await collectAxeViolations();
    const bad = violations.filter((v) => FAILING_IMPACTS.includes(v.impact));
    expect(
      bad.map((v) => `${v.id}@${v.impact}`).sort(),
      `axe violations: ${JSON.stringify(violations.map((v) => `${v.id}@${v.impact} nodes=${v.nodes.length}`))}`,
    ).toEqual([]);
    const fails = targetedFailures(page);
    expect(fails, `targeted failures: ${JSON.stringify(fails)}`).toEqual([]);
  });
});