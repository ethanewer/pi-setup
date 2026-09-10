import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/react';
import App from '../src/App.jsx';
import home from '../src/data/home.mjs';
import services from '../src/data/services.mjs';
import book from '../src/data/book.mjs';
import contact from '../src/data/contact.mjs';
import {
  prepareDocument,
  collectAxeViolations,
  targetedFailures,
  FAILING_IMPACTS,
} from '../tools/a11y.mjs';

const PAGES = [
  ['home', home, 'Home — Lanternwell Clinic'],
  ['services', services, 'Services — Lanternwell Clinic'],
  ['book', book, 'Book an appointment — Lanternwell Clinic'],
  ['contact', contact, 'Contact — Lanternwell Clinic'],
];

describe('Lanternwell Clinic pages', () => {
  for (const [slug, page, title] of PAGES) {
    it(`${slug}: renders and passes the accessibility gate`, async () => {
      prepareDocument(title);
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
  }
});
