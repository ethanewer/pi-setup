/* plinth-wicket hardened sanitizer.
 *
 * Built on the real DOMPurify 3.4.15 cloned to /app/src. Neutralizes the
 * script/behavior CSS mutation class inside `style` attribute values while
 * preserving legitimate CSS (including url(#...) fragment references) and
 * leaving all ordinary DOMPurify tag/attribute/handler stripping intact.
 *
 * Authored as the task's own contribution; applied at trial time by the oracle.
 */
'use strict';

const createDOMPurify = require('/app/src/dist/purify.cjs');
const jsdom = require('/app/src/node_modules/jsdom');

// Whitespace / control characters a browser folds out of a scheme name, mirror
// DOMPurify's own ATTR_WHITESPACE so obfuscation inside a url() is caught.
const WS = /[\u0000-\u0020\u00A0\u1680\u180E\u2000-\u2029\u205F\u3000]+/g;

const isWs = (c) => /\s/.test(c);

// Neutralize script/behavior CSS directives in one style-attribute value.
function sanitizeCssValue(css) {
  const s = String(css);
  const out = [];
  let i = 0;
  while (i < s.length) {
    const rest = s.slice(i);
    const m = rest.match(
      /^(expression|url|behavior|-moz-binding|-ms-binding)\b/i
    );
    if (!m) {
      out.push(s[i]);
      i++;
      continue;
    }
    const kw = m[1].toLowerCase();

    if (kw === 'expression') {
      // drop the whole expression(...) block (balanced parens)
      let j = i + m[0].length;
      while (j < s.length && isWs(s[j])) j++;
      if (j < s.length && s[j] === '(') {
        let depth = 0;
        let k = j;
        for (; k < s.length; k++) {
          if (s[k] === '(') depth++;
          else if (s[k] === ')') {
            depth--;
            if (depth === 0) break;
          }
        }
        i = k < s.length ? k + 1 : s.length;
        continue;
      }
      out.push(s[i]);
      i++;
      continue;
    }

    if (kw === 'url') {
      let j = i + m[0].length;
      while (j < s.length && isWs(s[j])) j++;
      if (j < s.length && s[j] === '(') {
        let depth = 0;
        let k = j;
        for (; k < s.length; k++) {
          if (s[k] === '(') depth++;
          else if (s[k] === ')') {
            depth--;
            if (depth === 0) break;
          }
        }
        const body = s.slice(j + 1, k);
        // Normalize obfuscation, strip quotes, then decide on the scheme.
        const normalized = body.replace(WS, '').replace(/^["']|["']$/g, '');
        const sm = normalized.match(/^([a-zA-Z][a-zA-Z0-9+.\-]*)\s*:/);
        let keep = true;
        if (sm) {
          const scheme = sm[1].toLowerCase();
          keep = !(
            scheme.includes('script') ||
            scheme === 'data' ||
            scheme === 'vbscript' ||
            scheme === 'mocha' ||
            scheme === 'about'
          );
        }
        if (keep) out.push(s.slice(i, k + 1));
        i = k < s.length ? k + 1 : s.length;
        continue;
      }
      out.push(s[i]);
      i++;
      continue;
    }

    // behavior / -moz-binding / -ms-binding: drop the whole declaration.
    let j = i;
    while (j < s.length && s[j] !== ';') j++;
    i = j < s.length ? j + 1 : s.length;
    continue;
  }
  return out.join('');
}

let cached = null;

function sanitize(html) {
  if (!cached) {
    const dom = new jsdom.JSDOM(
      '<!doctype html><html><body></body></html>',
      { runScripts: 'dangerously' }
    );
    const DOMPurify = createDOMPurify(dom.window);
    DOMPurify.addHook('beforeSanitizeAttributes', function (node) {
      if (!node || !node.attributes) return;
      for (let n = 0; n < node.attributes.length; n++) {
        const attr = node.attributes[n];
        if (attr.name.toLowerCase() === 'style') {
          attr.value = sanitizeCssValue(attr.value);
        }
      }
    });
    cached = (fragment) => DOMPurify.sanitize(String(fragment));
  }
  return cached(html);
}

module.exports = { sanitize };
