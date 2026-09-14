#!/usr/bin/env python3
"""Oracle step 1 for tackle-inlet: apply the upstream-shaped fix.

The Hungarian Snowball stemmer crashes on the empty string because its r1
region detection reads the first character of the word before checking
whether the word is empty. The upstream fix (and the oracle's fix) returns
the word unchanged at the very top of HungarianStemmer.stem(), before any
region computation runs. Every other supported Snowball language already
handles ''.

This script edits the checked-out tree in place: it inserts the guard right
after `word = word.lower()` in HungarianStemmer.stem(). It refuses to run if
the tree is already fixed or if the context it expects has changed.
"""

import sys

SNOWBALL = "/app/src/nltk/stem/snowball.py"

src = open(SNOWBALL, encoding="utf-8").read()

if "if not word:" in src:
    print("tree already carries an empty-string guard; not patching")
    sys.exit(0)

cls = src.index("class HungarianStemmer")
stopword_line = src.index("if word in self.stopwords:", cls)
insert_at = src.rindex("word = word.lower()", cls, stopword_line)

expected = "word = word.lower()\n\n        if word in self.stopwords:"
if src[insert_at:insert_at + len(expected)] != expected:
    sys.exit("unexpected context at the guard site; refusing to patch")

guard = "word = word.lower()\n\n        if not word:\n            return word"
src = src[:insert_at] + guard + src[insert_at + len("word = word.lower()"):]

with open(SNOWBALL, "w", encoding="utf-8") as fh:
    fh.write(src)

print("oracle: empty-string guard inserted into HungarianStemmer.stem()")