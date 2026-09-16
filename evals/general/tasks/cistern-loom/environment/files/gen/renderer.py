# -*- coding: utf-8 -*-
"""Marker renderer for the cistern corpus.

The corpus is authored once, in STRICT-correct form ("what a fully migrated
repository looks like"), and rendered in two modes:

  * strict - the marker text is kept: parameter and return annotations are
             present and non-null proofs appear as `!`.
  * loose  - the same runtime code with the type evidence stripped: an
             unannotated parameter becomes implicitly any under a non-strict
             tsconfig, and a proof site drops its `!`. Compiles under the
             shipped non-strict tsconfig; fails a strict compile exactly
             where a real migration has to re-add the evidence.

Markers understood by render():

  «A: TYPE»   placed right after an identifier or `)`: yields `: TYPE` in
              strict mode and an empty string in loose mode. Used for
              parameter and return annotations. Whitespace around the type
              is trimmed.
  «P»         placed right after an expression: yields `!` in strict mode
              and an empty string in loose mode. Used for non-null proofs.

Everything else is literal and identical in both modes. The shipped loose
repository contains no `any`, no `@ts-` comments and no casts: it only
lacks strictness evidence, which is the point of the migration.
"""

import re

_ANN = re.compile("\xabA:(.*?)\xbb")
_PROOF = "\xabP\xbb"


def render(text, strict):
    if strict:
        out = _ANN.sub(lambda m: ": " + m.group(1).strip(), text)
        out = out.replace(_PROOF, "!")
    else:
        out = _ANN.sub("", text)
        out = out.replace(_PROOF, "")
    return out