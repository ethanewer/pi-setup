'use strict';
// marline-tiller verifier harness prototype (CJS).
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');

const PKG = '/app/package.json';
const APP = '/app';
const DIST = '/app/dist';
const COMPONENTS = ['Counter', 'QuantityInput', 'TagPicker'];
const failures = [];
const fail = (m) => failures.push(m);

function q(parent, sel) {
  const attrRe = /\[([a-z-]+)=([^\]]*)\]/g;
  const m = /^([a-z]+)?(.*)$/.exec(sel);
  const tag = m[1];
  const attrs = [];
  let mm;
  let rest = m[2];
  while ((mm = attrRe.exec(rest)) !== null) attrs.push([mm[1], mm[2]]);
  const all = parent.querySelectorAll(tag || '*');
  for (const el of all) {
    let ok = true;
    for (const [k, v] of attrs) {
      if (el.getAttribute(k) !== v) { ok = false; break; }
    }
    if (ok) return el;
  }
  return null;
}

async function main() {
  // ---------- 0. static build contract ----------
  if (!fs.existsSync(PKG)) {
    fail('missing deliverable /app/package.json');
  } else {
    console.log('build: starting npm run build');
    try {
      execFileSync('npm', ['run', 'build'], { cwd: APP, stdio: ['ignore', 'pipe', 'pipe'], timeout: 420000 });
      console.log('build: ok');
    } catch (e) {
      const msg = (e.stderr || e.stdout || String(e)).toString();
      fail('npm run build failed: ' + msg.split('\n').slice(-8).join(' | '));
    }
  }

  const esmPath = path.join(DIST, 'marline-lib.mjs');
  if (!fs.existsSync(esmPath)) {
    fail('dist/marline-lib.mjs missing (ESM artifact was not emitted)');
  } else {
    const src = fs.readFileSync(esmPath, 'utf8');
    if (!/\bexport\b/.test(src)) fail('dist/marline-lib.mjs contains no export statements');
    if (/module\.exports/.test(src)) fail('dist/marline-lib.mjs looks like CJS output');
    if (src.length < 200) fail('dist/marline-lib.mjs suspiciously small (' + src.length + ' bytes)');
  }
  const indexDts = path.join(DIST, 'index.d.ts');
  if (!fs.existsSync(indexDts)) {
    fail('dist/index.d.ts missing (no type declarations emitted)');
  } else {
    const decl = fs.readFileSync(indexDts, 'utf8');
    for (const n of COMPONENTS) {
      if (!decl.includes(n)) fail('dist/index.d.ts does not declare ' + n);
    }
  }
  const walkDts = (dir) => {
    const out = [];
    for (const de of fs.readdirSync(dir, { withFileTypes: true })) {
      const p2 = path.join(dir, de.name);
      if (de.isDirectory()) out.push(...walkDts(p2));
      else if (de.name.endsWith('.d.ts')) out.push(p2);
    }
    return out;
  };
  const dtsCount = fs.existsSync(DIST) ? walkDts(DIST).length : 0;
  if (dtsCount < 4) fail('only ' + dtsCount + ' .d.ts file(s) under dist; expected per-module declarations');

  // ---------- 0b. the repository's own test suite must be green ----------
  // The instruction's success criterion 1 requires `npm test` to exit 0.
  // This gate is independent of the prop-fixture battery below: the battery
  // asserts the README contract against the BUILT library, this gate asserts
  // the shipped suite itself is not red (which also catches a solution that
  // deletes or disables the suite).
  try {
    execFileSync('npm', ['test'], { cwd: APP, stdio: ['ignore', 'pipe', 'pipe'], timeout: 300000 });
    console.log('npm test: ok');
  } catch (e) {
    const msg = (e.stderr || e.stdout || String(e)).toString();
    fail('npm test is red (repository suite must exit 0): ' + msg.split('\n').slice(-6).join(' | '));
  }

  // ---------- 1. jsdom environment ----------
  const { JSDOM } = require('jsdom');
  const dom = new JSDOM('<!doctype html><html><body></body></html>', { url: 'http://localhost/' });
  const w = dom.window;
  globalThis.DOM = dom;
  for (const k of ['window','document','navigator','Node','Element','HTMLElement',
                   'HTMLInputElement','HTMLButtonElement','HTMLOutputElement',
                   'HTMLSpanElement','HTMLDivElement','HTMLLIElement','HTMLUListElement',
                   'Document','Event','MouseEvent','KeyboardEvent','UIEvent','FocusEvent',
                   'MutationObserver','NodeList','HTMLCollection','File','Blob','FormData',
                   'XMLHttpRequest','getComputedStyle','history','Text','Comment',
                   'DocumentFragment','KeyboardEvent','DOMParser']) {
    try { globalThis[k] = w[k]; } catch (_) {}
  }
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;

  let lib;
  if (fs.existsSync(esmPath)) {
    try {
      lib = await import(pathToFileURL(esmPath).href);
      console.log('import built lib: exports =', Object.keys(lib).sort().join(','));
    } catch (e) {
      fail('failed to import built ESM module: ' + String(e));
      lib = null;
    }
  }
  if (!lib) {
    report();
    return;
  }
  for (const n of COMPONENTS) {
    if (typeof lib[n] !== 'function') fail('built library does not export component ' + n);
  }

  const React = require('react');
  const ReactDOM = require('react-dom');
  const { render, cleanup, fireEvent } = require('@testing-library/react');

  const runs = [];
  const cases = process.argv.slice(2).filter((a) => a.endsWith('.json'));
  const renderedAny = false;

  function runRender(spec) {
    const label = spec.component + ' / ' + (spec.label || '?');
    if (typeof lib[spec.component] !== 'function') { fail(label + ': component missing'); return; }
    const captured = {};
    const props = { ...spec.props };
    for (const p of spec.capture || []) {
      captured[p] = [];
      const orig = typeof props[p] === 'function' ? props[p] : null;
      props[p] = (...a) => { captured[p].push(a); if (orig) orig(...a); };
    }
    let out;
    try {
      out = render(React.createElement(lib[spec.component], props));
    } catch (e) {
      fail(label + ': render threw: ' + String(e));
      return;
    }
    const { container, rerender } = out;
    let failed = false;
    const runCheck = (c) => {
      const el = q(container, c.selector);
      if (c.kind === 'text') {
        if (!el) fail(label + ': check text: no match for ' + c.selector);
        else if (el.textContent !== c.eq) fail(label + ': check text: ' + c.selector + ' = ' + JSON.stringify(el.textContent) + ', want ' + JSON.stringify(c.eq));
      } else if (c.kind === 'text-contains') {
        if (!el) fail(label + ': check text-contains: no match for ' + c.selector);
        else if (!el.textContent.includes(c.contains)) fail(label + ': check text-contains: ' + JSON.stringify(el.textContent) + ' lacks ' + JSON.stringify(c.contains));
      } else if (c.kind === 'attr') {
        if (!el) fail(label + ': check attr: no match for ' + c.selector);
        else {
          const v = el.getAttribute(c.attr);
          if (v !== c.eq) fail(label + ': check attr: ' + c.selector + '[' + c.attr + '] = ' + JSON.stringify(v) + ', want ' + JSON.stringify(c.eq));
        }
      } else if (c.kind === 'present') {
        if (!el) fail(label + ': check present: no match for ' + c.selector);
      } else if (c.kind === 'absent') {
        if (el) fail(label + ': check absent: ' + c.selector + ' unexpectedly present');
      } else if (c.kind === 'class') {
        if (!el) fail(label + ': check class: no match for ' + c.selector);
        else if (!el.classList.contains(c.has)) fail(label + ': check class: ' + c.selector + ' lacks class ' + c.has);
      } else if (c.kind === 'class-not') {
        if (!el) fail(label + ': check class-not: no match for ' + c.selector);
        else if (el.classList.contains(c.has)) fail(label + ': check class-not: ' + c.selector + ' must not have class ' + c.has);
      } else {
        fail(label + ': unknown check kind ' + c.kind);
      }
    };
    for (const c of spec.check || []) runCheck(c);
    for (const step of spec.steps || []) {
      if (step.rerender) {
        try {
          rerender(React.createElement(lib[spec.component], { ...props, ...step.rerender }));
        } catch (e) {
          fail(label + ': rerender threw: ' + String(e));
        }
      }
      for (const a of step.actions || []) {
        const el = q(container, a.selector);
        if (!el) { fail(label + ': action target not found: ' + a.selector); continue; }
        try {
          if (a.kind === 'click') fireEvent.click(el);
          else if (a.kind === 'type') fireEvent.change(el, { target: { value: a.text } });
          else if (a.kind === 'key') fireEvent.keyDown(el, { key: a.key });
          else if (a.kind === 'blur') fireEvent.blur(el);
          else fail(label + ': unknown action kind ' + a.kind);
        } catch (e) {
          fail(label + ': action ' + a.kind + ' threw: ' + String(e));
        }
      }
      for (const c of step.check || []) runCheck(c);
      for (const [prop, expected] of Object.entries(step.callback || {})) {
        const got = JSON.stringify(captured[prop] || []);
        if (JSON.stringify(expected) !== got) {
          fail(label + ': callback ' + prop + ' after step = ' + got + ', want ' + JSON.stringify(expected));
        }
      }
    }
    if (spec.freshProps) {
      for (const [prop, propName] of Object.entries(spec.freshProps)) {
        const propVal = spec.props[propName];
        for (const args of captured[prop] || []) {
          if (args.length > 0 && args[0] === propVal) {
            fail(label + ': callback ' + prop + ' received the props ' + propName + ' array itself (mutation/aliasing)');
          }
        }
      }
    }
    try { cleanup(); } catch (_) {}
  }

  for (const casePath of cases) {
    let fixture;
    try {
      fixture = JSON.parse(fs.readFileSync(casePath, 'utf8'));
    } catch (e) {
      fail('cannot read fixture ' + casePath + ': ' + String(e));
      continue;
    }
    for (const r of fixture.renders || []) runRender(r);
  }

  report();

  function report() {
    if (failures.length) {
      console.log('VERIFIER FAILURES (' + failures.length + '):');
      for (const f of failures) console.log('  - ' + f);
      process.exitCode = 1;
    } else {
      console.log('ALL CHECKS PASSED');
      process.exitCode = 0;
    }
  }
  void renderedAny;
}

main().catch((e) => {
  console.error('harness crashed: ' + String(e));
  process.exitCode = 1;
});
