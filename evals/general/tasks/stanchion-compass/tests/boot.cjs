'use strict';
// stanchion-compass per-case boot: loads the BUILT entry chunk into a fresh
// jsdom, navigates to the case's route and asserts the route chunk was
// fetched and executed (ready content + interaction checks).
//
// Runs as its own process per case so module state (react roots, chunk
// import cache, globals) never leaks between cases.
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

const [entryFile, caseFile] = process.argv.slice(2);
if (!entryFile || !caseFile) {
  console.error('usage: node boot.cjs <entryChunkFile> <case.json>');
  process.exit(1);
}

const c = JSON.parse(fs.readFileSync(caseFile, 'utf8'));
const { JSDOM } = require('jsdom');

const failures = [];
const fail = (m) => failures.push(m);

let DOM_DOC = null; // set once the jsdom document exists

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitFor(fn, ms, step = 60) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (fn()) return true;
    await sleep(step);
  }
  return fn();
}

const textOf = (sel) => {
  const el = DOM_DOC && DOM_DOC.querySelector(sel);
  return el ? (el.textContent || '').trim() : null;
};

async function main() {
  const dom = new JSDOM(
    '<!doctype html><html><head></head><body><div id="root"></div></body></html>',
    { url: 'http://localhost/', pretendToBeVisual: true }
  );
  const w = dom.window;
  DOM_DOC = dom.window.document;

  const globals = [
    'window', 'self', 'document', 'navigator', 'location', 'history',
    'Node', 'Element', 'HTMLElement', 'DocumentFragment', 'Document',
    'Text', 'Comment', 'Event', 'CustomEvent', 'MouseEvent', 'KeyboardEvent',
    'FocusEvent', 'UIEvent', 'InputEvent', 'MutationObserver',
    'HTMLDivElement', 'HTMLSpanElement', 'HTMLUListElement', 'HTMLLIElement',
    'HTMLAnchorElement', 'HTMLButtonElement', 'HTMLOutputElement',
    'HTMLParagraphElement', 'HTMLHeadingElement', 'HTMLTableElement',
    'HTMLTableRowElement', 'HTMLTableCellElement', 'HTMLTableSectionElement',
    'HTMLHeadElement', 'HTMLBodyElement', 'HTMLScriptElement',
    'HTMLLinkElement', 'HTMLStyleElement', 'HTMLMetaElement', 'HTMLTitleElement',
    'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame',
    'getSelection', 'matchMedia',
  ];
  for (const k of globals) {
    if (typeof w[k] !== 'undefined') {
      // Node exposes a few of these (e.g. globalThis.navigator) as
      // getter-only properties; fall back to a configurable defineProperty
      // or skip when the property is not overridable.
      try {
        globalThis[k] = w[k];
      } catch (e1) {
        try {
          Object.defineProperty(globalThis, k, {
            value: w[k], writable: true, configurable: true,
          });
        } catch (e2) {
          fail('could not set global ' + k + ': ' + String(e2));
        }
      }
    }
  }
  if (!globalThis.requestAnimationFrame) {
    globalThis.requestAnimationFrame = (cb) => setTimeout(() => cb(Date.now()), 16);
    globalThis.cancelAnimationFrame = (id) => clearTimeout(id);
  }
  if (!w.performance.getEntriesByName) w.performance.getEntriesByName = () => [];
  if (!w.performance.getEntriesByType) w.performance.getEntriesByType = () => [];

  // Vite's modulepreload polyfill uses fetch() when the runtime does not
  // advertise modulepreload support (jsdom's link.relList has no supports()).
  // The app is fully offline and makes no network requests; the fetch calls
  // are cosmetic preloads only, so no-op them to keep the boot deterministic.
  const noopFetch = () => Promise.resolve(new globalThis.Response('', { status: 200 }));
  try {
    globalThis.fetch = noopFetch;
  } catch (e) {
    try {
      Object.defineProperty(globalThis, 'fetch', {
        value: noopFetch, writable: true, configurable: true,
      });
    } catch (e2) { /* ignore */ }
  }

  // Boot the built bundle: this executes main.tsx, which mounts the app into
  // #root. Lazy route chunks load from /app/dist/assets on demand.
  await import(pathToFileURL(entryFile).href);

  // The app's default route is home. The instruction requires it to render
  // before we navigate anywhere, so assert it here: a solution that breaks
  // the home branch (e.g. drops it from the route switch) must not score.
  const homeOk = await waitFor(() => {
    const el = dom.window.document.querySelector('[data-testid=home-head]');
    return !!el && (el.textContent || '').includes('Console home');
  }, 12000);
  if (!homeOk) {
    const got = textOf('[data-testid=home-head]');
    fail('default route: home did not render (expected [data-testid=home-head] containing "Console home", got "' + (got || '') + '")');
    return 1;
  }
  console.log('home: default route renders');

  // Navigate to the case route.
  try {
    w.location.hash = c.route;
  } catch (e) {
    // jsdom versions vary in hash navigation support; fall back to a
    // property swap + explicit event.
    try {
      Object.defineProperty(w.location, 'hash', { value: c.route, configurable: true });
    } catch (e2) {
      fail('could not set location.hash: ' + String(e2));
    }
  }
  w.dispatchEvent(new w.Event('hashchange'));

  // -- ready: the route chunk must be fetched and rendered --
  const ready = c.ready || [];
  for (const r of ready) {
    const ok = await waitFor(() => {
      const el = dom.window.document.querySelector(r.selector);
      return !!el && (el.textContent || '').includes(r.contains);
    }, 12000);
    if (!ok) {
      const got = textOf(r.selector);
      fail('ready[' + r.selector + ']: expected text containing "' + r.contains + '", got "' + (got || '') + '"');
    }
  }

  // -- steps: interactions powered by the route's heavy module --
  const before = {};
  for (const step of c.steps || []) {
    for (const ch of step.checks || []) {
      if (ch.changed) before[ch.selector] = textOf(ch.selector);
    }
    if (step.action.kind === 'click') {
      const btn = dom.window.document.querySelector(step.action.selector);
      if (!btn) {
        fail('step: element ' + step.action.selector + ' not found');
        continue;
      }
      btn.dispatchEvent(new w.MouseEvent('click', { bubbles: true, cancelable: true, view: w }));
      await sleep(200);
    }
    for (const ch of step.checks || []) {
      const ok = await waitFor(() => {
        const el = dom.window.document.querySelector(ch.selector);
        if (!el) return false;
        const txt = (el.textContent || '').trim();
        if (ch.changed) return txt.length > 0 && txt !== before[ch.selector] && before[ch.selector] != null;
        if (ch.nonempty) return txt.length > 0;
        if (ch.matches) return new RegExp(ch.matches).test(txt);
        return true;
      }, 4000);
      const got = textOf(ch.selector);
      if (!ok) {
        fail('step check [' + ch.selector + ']: expected ' +
          (ch.changed ? 'changed' : ch.nonempty ? 'non-empty' : 'match ' + ch.matches) +
          ', got "' + (got || '') + '"');
      }
    }
  }

  if (failures.length > 0) {
    console.error(failures.join('\n'));
    process.exit(1);
  }
  console.log('boot ' + (c.label || caseFile) + ': ok');
  process.exit(0);
}

// main() may exit early on the home check with return 1; keep the exit code
// contract in one place.
main().then((code) => process.exit(code || 0)).catch((e) => {
  console.error('boot crashed: ' + (e && e.stack ? e.stack : String(e)));
  process.exit(1);
});