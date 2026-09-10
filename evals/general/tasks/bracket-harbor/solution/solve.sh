#!/usr/bin/env bash
# Oracle for bracket-harbor.
#
# Diagnoses the precedence-tier regression in package token (introduced by
# the operator-tier refactor two commits back), restores the documented
# ladder in Kind.Precedence(), re-verifies the whole tree with the go
# toolchain, and writes the required /app/fix.md write-up. The solver never
# reads /tests and performs the real fix an engineer would apply.
set -euo pipefail

REPO=/app/bh/
mkdir -p /app/bh/
OP="$REPO/internal/token/op.go"

# ------------------------------------------------------------------- the fix
python3 - "$OP" <<'PY'
import re
import sys

path = sys.argv[1]
src = open(path).read()

# Locate the KindOr case inside Precedence(). The refactor folded OR onto the
# AND tier (return 3) and annotated the case; restore the contract (return 2).
pattern = re.compile(
    r'\tcase KindOr:\n(?:[ \t]*//[^\n]*\n)*\t\treturn ([23])\n',
)
m = pattern.search(src)
if m is None:
    sys.exit("op.go does not contain a recognisable KindOr precedence case; aborting")
if m.group(1) == "2":
    sys.exit("KindOr already returns 2; the regression is not present")
src = src[:m.start()] + "\tcase KindOr:\n\t\treturn 2\n" + src[m.end():]
open(path, "w").write(src)
print("precedence(): KindOr tier restored from 3 to 2")
PY

gofmt -w "$OP"

# ------------------------------------------------------- verify the repair
( cd "$REPO" && go build ./... && go vet ./... && go test ./... )

# ------------------------------------------------------------- write the log
cat > /app/fix.md <<'MD'
# bh: boolean-tier precedence repair

## Symptom

`go test ./...` fails, and only one test in the whole tree: the query
package's grouping suite:

```
--- FAIL: TestConditionGrouping (0.00s)
    query_test.go:33: case 0: "p = 1 OR q = 2 AND r = 3" groups as
    "and(or(eq(p, 1), eq(q, 2)), eq(r, 3))", want
    "or(eq(p, 1), and(eq(q, 2), eq(r, 3)))"
```

## Root cause

The parse tree for a condition is produced by the parser's
precedence-climbing loop, which delegates every grouping decision to
`token.Kind.Precedence()`. The refactor commit
"refactor(token): fold boolean operator precedence tiers" (two commits back
in `git log`) rewrote the OR case of that table so that `KindOr` returned 3,
the same tier as `KindAnd`.

With the two boolean operators on one tier, and the loop breaking on
`prec <= minPrec`, `p = 1 OR q = 2 AND r = 3` re-grouped left-to-right:
`(p = 1 OR q = 2) AND r = 3` instead of the canonical
`p = 1 OR (q = 2 AND r = 3)`. The doc comment above the table still
advertised OR = 2 / AND = 3, so the code silently violated the ladder every
consumer parses against.

## Fix

`internal/token/op.go`, `Precedence()`: restore the OR case to tier 2.

```
OR                                  2
AND                                 3
=  !=  <  <=  >  >=                 4
IN  LIKE  NOT LIKE  BETWEEN         4
```

That is the only change needed: nothing in the parser, the lexer or the
query package was at fault, and the tests themselves were correct all along.

## Verification

- `go build ./...` — passes
- `go vet ./...`   — passes
- `go test ./...`  — passes (including TestConditionGrouping)
MD

echo "fix written and suite green"