#!/bin/bash
# cistern-ferry oracle: apply the upstream fix to the real prettier tree at
# /app/src and prove the user-facing repro now succeeds.
#
# The bug: attribute-name normalization in the HTML language postprocess
# lowercased an attribute name only when the element had an entry in
# Prettier's per-element attribute table, so a known attribute like class on
# a well-known tag without per-element data (e.g. <span>) stayed uppercase
# while the same attribute on <div> was lowercased. The fix keys the
# decision off HTML_TAGS (is this a known HTML tag at all) and uses a
# null-safe per-element lookup, so global attributes (class, id, ...) are
# lowercased on every well-known tag without per-element data as well.
set -eu

python3 - <<'PY'
path = '/app/src/src/language-html/parse/postprocess.js'
with open(path, encoding='utf-8') as fh:
    src = fh.read()

old = """              ELEMENT_ATTRIBUTES.has(node.name) &&
              (GLOBAL_ATTRIBUTES.has(lowerCasedAttrName) ||
                ELEMENT_ATTRIBUTES.get(node.name).has(lowerCasedAttrName)),"""
new = """              HTML_TAGS.has(node.name) &&
              (GLOBAL_ATTRIBUTES.has(lowerCasedAttrName) ||
                ELEMENT_ATTRIBUTES.get(node.name)?.has(lowerCasedAttrName)),"""

hits = src.count(old)
assert hits == 1, 'expected exactly one ELEMENT_ATTRIBUTES-gated normalization, found %d' % hits
assert new not in src, 'HTML_TAGS check already present; tree is not at the pre-fix parent'
open(path, 'w', encoding='utf-8').write(src.replace(old, new))
print('patched: attribute names on known HTML tags are normalized to lowercase')
print('regardless of whether the tag has per-element attribute data')
PY

# Syntax-check the touched source file, then run the user-facing repro: it
# must print both attributes lowercased and exit 0.
node --check /app/src/src/language-html/parse/postprocess.js
cd /app/src
node /app/reproduce.js
echo 'oracle: /app/reproduce.js exits 0 with consistent lowercase attributes'