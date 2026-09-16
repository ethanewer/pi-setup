#!/bin/bash
# extract-golden.sh — build-time helper for the cistern-bridge task.
#
# /opt/golden/test-suite.js is the project's own test-suite.js as of the FIX
# commit, extracted by the Dockerfile with `git show <FIX_SHA>:test/test-suite.js`
# (upstream bytes never enter this repository's tree). This script derives from
# it the targeted regression module for the case-preserving-attribute defect:
# the six tests of the "case-preserving attribute" block (four regression tests
# plus a string-input control and a DOMParser-variant test), wrapped in a QUnit
# module factory the verifier can load directly.
#
# The rawtext / literal-text sub-block that precedes this one in the same file
# exercises a *different* defect from the same upstream commit; it is not part
# of this task's scope and is deliberately not included.
set -euo pipefail

SRC=${GOLDEN_SRC:-/opt/golden/test-suite.js}
OUT=${GOLDEN_OUT:-/opt/golden/cistern-suite.js}

test -s "$SRC" || { echo "extract-golden: $SRC missing" >&2; exit 1; }

python3 - "$SRC" "$OUT" <<'PYEOF'
import re, sys

src = open(sys.argv[1], encoding="utf-8").read()

start_marker = (
    "Uppercase / mixed-case attribute from a case-preserving node survives"
)
end_marker = "Rawtext/literal-text element carrying an element child"

start = src.index(start_marker)
# The block-comment opener directly precedes the marker; start the slice there
# so the leading comment stays a valid JS block comment.
opener = src.rfind("\n    /*\n", 0, start)
assert opener > 0, "could not locate slice block-comment opener"
start = opener + 1  # keep the newline
end = src.index(end_marker)
# Back up to the close of the DOMParser test (');') so the slice ends on a
# complete statement and the rawtext comment opener is not included.
end = src.rfind("    );", 0, end)
assert end > start, "could not locate slice close"

body = src[start:end + len("    );\n")]
assert body.count("QUnit.test(") == 6, f"expected 6 tests, found {body.count('QUnit.test(')}"

out = """// Derived at image-build time from /opt/golden/test-suite.js (upstream
// test-suite.js at the fix commit). Wraps the upstream regression tests for
// case-preserving attribute names on DOM-node input in a QUnit module factory.
module.exports = function (DOMPurify, window) {
  const document = window.document;
  QUnit.module('golden: case-preserving attribute removal (DOM-node input)');
""" + body + "};\n"

open(sys.argv[2], "w", encoding="utf-8").write(out)
print(f"wrote {sys.argv[2]} ({len(body)} bytes of upstream test body)")
PYEOF