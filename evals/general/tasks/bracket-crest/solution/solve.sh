#!/bin/bash
# bracket-crest oracle: apply the upstream fix to the real prettier tree at
# /app/src and prove the user-facing repro now succeeds.
#
# The bug: a Markdown setext heading whose text spans several raw source
# lines, written inside a blockquote, was corrupted on format because
# splitTextIntoSentences only looked for a 'paragraph' ancestor when deciding
# how to treat an original raw line, so the heading's lines were joined with
# embedded blockquote markers ("> Multi > Line"). The fix recognises a
# 'heading' ancestor as well, so every continuation line keeps its own
# blockquote marker and the reformatted file means the same thing as the
# input.
set -eu

python3 - <<'PY'
path = '/app/src/src/language-markdown/print/preprocess.js'
with open(path, encoding='utf-8') as fh:
    src = fh.read()

old = '''    const paragraphIndex = parentStack.findIndex(
      (ancestor) => ancestor?.type === "paragraph",
    );'''
new = '''    const paragraphIndex = parentStack.findIndex(
      (ancestor) =>
        ancestor?.type === "paragraph" || ancestor?.type === "heading",
    );'''

hits = src.count(old)
assert hits == 1, 'expected exactly one paragraph-only findIndex call, found %d' % hits
assert new not in src, 'heading check already present; tree is not at the pre-fix parent'
open(path, 'w', encoding='utf-8').write(src.replace(old, new))
print('patched: splitTextIntoSentences also treats "heading" ancestors as')
print('multi-line content, so setext headings in blockquotes keep one marker')
print('per source line')
PY

# Syntax-check the touched source file, then run the user-facing repro: it
# must print the input file back unchanged and diff cleanly.
node --check /app/src/src/language-markdown/print/preprocess.js
cd /app/src
node bin/prettier.js /app/reproduce.md > /tmp/crest_oracle_out.md
diff -q /app/reproduce.md /tmp/crest_oracle_out.md
echo 'oracle: /app/reproduce.md formatted back to itself'