// Shared accessibility audit helpers for Lanternwell Clinic.
// Used by the visible test suite and by the task verifier's hidden pages.
import axe from 'axe-core';

// axe rules that cannot be measured under jsdom: they need real browser
// geometry and a computed stylesheet render. Colour-only state is asserted
// by the targeted checks instead.
export const DISABLED_RULES = {
  'color-contrast': { enabled: false },
  'target-size': { enabled: false },
};

// Violation impacts that fail a page. Minor-impact findings are tolerated
// because several best-practice heuristics cannot be resolved under jsdom.
export const FAILING_IMPACTS = ['moderate', 'serious', 'critical'];

function prepareDocument(title) {
  document.documentElement.setAttribute('lang', 'en');
  if (!document.querySelector('title')) {
    const t = document.createElement('title');
    document.head.appendChild(t);
  }
  document.querySelector('title').textContent = title || 'Lanternwell Clinic';
}

async function collectAxeViolations() {
  const results = await axe.run(document, { rules: DISABLED_RULES });
  return results.violations;
}

export const FOCUSABLE =
  'a[href],area[href],button,input,select,textarea,' +
  '[tabindex]:not([tabindex="-1"])';

function isHidden(el) {
  if (el.hidden) return true;
  return el.getAttribute('aria-hidden') === 'true';
}

function focusables() {
  return [...document.querySelectorAll(FOCUSABLE)].filter(
    (el) => !isHidden(el) && el.getAttribute('tabindex') !== '-1',
  );
}

function visible(s) {
  return (s || '').replace(/\s+/g, ' ').trim();
}

const STATE_WORDS = { open: 'open', busy: 'busy', closed: 'closed' };

// Form controls (exclude hidden/button flavours, which have their own rules).
const CONTROL_SEL =
  'input:not([type="hidden"]):not([type="submit"]):not([type="button"])' +
  ':not([type="reset"]):not([type="image"]), select, textarea';

function targetedFailures(page) {
  const fails = [];

  // 1. skip link: the first focusable element is a link to the main region.
  const focus = focusables();
  const first = focus[0];
  if (!first) {
    fails.push('page has no focusable elements at all');
  } else if (
    first.tagName.toLowerCase() !== 'a' ||
    !(first.getAttribute('href') || '').endsWith('#main-content')
  ) {
    fails.push('first focusable element is not the skip link (expected href ending in #main-content)');
  } else if (!/skip/i.test(first.textContent || '')) {
    fails.push('skip link text does not mention "skip"');
  }
  if (!document.getElementById('main-content')) {
    fails.push('no element with id="main-content" to receive the skip');
  }

  // 2. focus order: main content precedes the supporting sidebar in DOM order.
  const mainEl = document.querySelector('main#main-content, [role="main"]');
  const asideEl = document.querySelector('aside, [role="complementary"]');
  const idxOf = (ancestor) => {
    return focus.findIndex((el) => ancestor && ancestor.contains(el));
  };
  const mainIdx = idxOf(mainEl);
  const asideIdx = idxOf(asideEl);
  if (mainIdx < 0) fails.push('main region contains no focusable element');
  if (asideIdx < 0) fails.push('sidebar region contains no focusable element');
  if (mainIdx >= 0 && asideIdx >= 0 && mainIdx > asideIdx) {
    fails.push('sidebar is reached in tab order before the main content');
  }

  // 3. live region: the announcement text is rendered inside a live region.
  const wanted = visible(page.announcement || '');
  if (wanted === '') {
    fails.push('page has no announcement text to check');
  } else {
    const candidates = [...document.querySelectorAll('*')]
      .filter((el) => visible(el.textContent || '') === wanted)
      .sort((a, b) => {
        let da = 0;
        let db = 0;
        for (let p = a; p && p !== document.body; p = p.parentElement) da += 1;
        for (let p = b; p && p !== document.body; p = p.parentElement) db += 1;
        return db - da; // outermost candidates first -> MAX textContent match
      });
    if (candidates.length === 0) {
      fails.push('announcement text is not rendered');
    } else {
      const el = candidates[0];
      const liveAttr = el.getAttribute('aria-live');
      const isLive =
        el.getAttribute('role') === 'status' ||
        (liveAttr != null && liveAttr !== '');
      if (!isLive) {
        fails.push('announcement is not inside a live region (role=status or aria-live)');
      }
    }
  }

  // 4. colour is never the only signal: every colour-coded status indicator
  //    exposes its state as text or an accessible name.
  for (const el of document.querySelectorAll('[data-state]')) {
    const word = STATE_WORDS[el.getAttribute('data-state')];
    if (!word) continue;
    const text = visible(el.textContent || '').toLowerCase();
    const ariaName = (el.getAttribute('aria-label') || '').toLowerCase();
    if (!text.includes(word) && !ariaName.includes(word)) {
      fails.push(`status indicator for "${el.getAttribute('data-state')}" carries no textual state`);
    }
  }

  // 5. every form control has an explicitly associated label (placeholder
  //    alone is not a label).
  for (const el of document.querySelectorAll(CONTROL_SEL)) {
    if (isHidden(el)) continue;
    const id = el.getAttribute('id') || '';
    const hasWrappingLabel = !!el.closest('label');
    const hasForLabel = id !== '' &&
      [...document.querySelectorAll('label[for]')].some(
        (l) => l.getAttribute('for') === id,
      );
    const hasAria =
      (el.getAttribute('aria-label') || '').trim() !== '' ||
      (el.getAttribute('aria-labelledby') || '').trim() !== '';
    if (!hasWrappingLabel && !hasForLabel && !hasAria) {
      fails.push(`form control "${id || el.getAttribute('name') || '(no name)'}" has no explicit label`);
    }
  }

  // 6. exactly one h1 per page (the axe heading-order rule does not enforce
  //    uniqueness).
  const h1s = [...document.querySelectorAll('h1')];
  if (h1s.length !== 1) {
    fails.push(`expected exactly one h1 on the page, found ${h1s.length}`);
  }

  // 7. every form control promised by the page data is actually rendered
  //    (the label contract cannot be "fixed" by deleting controls).
  if (page.form && page.form.fields) {
    for (const field of page.form.fields) {
      const rendered = [...document.querySelectorAll(CONTROL_SEL)].some((el) =>
        (el.getAttribute('id') || el.getAttribute('name')) === field.name,
      );
      if (!rendered) {
        fails.push(`form control "${field.name}" from the page data is not rendered`);
      }
    }
  }

  // 8. every content image promised by the page data is rendered and exposes
  //    the data's alt text (deleting images or substituting a generic alt is
  //    not a fix).
  if (page.cards) {
    for (const card of page.cards) {
      const im = card.image;
      if (!im || !im.src) continue;
      const matches = [...document.querySelectorAll('img')].filter(
        (el) => el.getAttribute('src') === im.src,
      );
      if (matches.length === 0) {
        fails.push(`content image ${im.src} is not rendered on the page`);
      } else if (!matches.some((el) => (el.getAttribute('alt') || '') === (im.alt || ''))) {
        fails.push(`content image ${im.src} does not expose its page-data alt text`);
      }
    }
  }

  return fails;
}

export { prepareDocument, collectAxeViolations, targetedFailures };