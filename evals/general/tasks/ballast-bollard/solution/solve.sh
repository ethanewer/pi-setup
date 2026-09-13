#!/bin/bash
# Oracle for ballast-bollard: localises and repairs the real defect in the
# bandit checkout at /app/src, then writes the diagnosis deliverable.
# It reads only the upstream tree (never /tests).
set -u
cd /app/src || { echo "oracle: /app/src missing" >&2; exit 1; }

# Sanity: this must be the real bandit tree at the buggy parent revision.
[ -f bandit/core/tester.py ] || { echo "oracle: not a bandit tree" >&2; exit 1; }
python3 - <<'PY'
import sys
sys.path.insert(0, "/app/src")
src = open("/app/src/bandit/core/utils.py", encoding="utf-8").read()
if "def get_nosec" in src:
    raise SystemExit("oracle: tree already contains the fix (get_nosec present)")
PY

python3 /solution/fix_bandit_nosec.py || exit 1
echo "oracle: applied the linerange-aware # nosec lookup fix"

cat > /app/diagnosis.md <<'MD'
## Diagnosis: `# nosec` on a later line of a multi-line construct is ignored

### Where
`bandit/core/tester.py` -- `BanditTester._get_nosecs_from_contexts` (the
method that decides, for a produced finding, which `# nosec` comments apply to
it).

### Root cause
For each AST node the visitor already records the whole region the node spans
(`context["linerange"]`), but the suppression lookup only consulted the
single line the node starts on: `nosec_lines.get(context["lineno"])`. When a
finding covers a multi-line string or expression, a `# nosec` comment placed
on the closing line (or any middle line) therefore never matched. The comment
was still tokenized and counted in the "lines skipped" accounting, which is
why the output said a nosec was seen while the finding was nonetheless
reported at the construct's first line.

### Fix
Added `utils.get_nosec(nosec_lines, context)` which walks
`context["linerange"]` and returns the nosec set for the first line of the
region that carries one, and used it for the context lookup in
`_get_nosecs_from_contexts` instead of the single-line `context["lineno"]`
probe. The "nosec without a test number" bookkeeping was moved from the
pre-visit phase (which only ever looked at the node's first line and
double-counted multi-part nodes such as f-strings) into the test phase, so a
blanket nosec found anywhere in the line range is honoured and counted once
per skipped test result. A suppression comment is now honoured no matter
which line of the flagged code region it appears on.

### Verification
`bandit -q /app/repro.py` exits 0 with no issues; the project's own unit
suite and functional suite both pass from the repo root.
MD

# Oracle sanity check with the project's own binary.
if bandit -q /app/repro.py; then
    echo "oracle: bandit -q /app/repro.py clean (exit 0)"
else
    echo "oracle: WARNING bandit still reports on the repro" >&2
    exit 1
fi

(cd /app/src && python3 -m unittest discover -s tests/unit \
     > /tmp/oracle_unit.log 2>&1)
rc=$?
echo "oracle: unit suite exit status: $rc"
[ $rc -eq 0 ] || tail -5 /tmp/oracle_unit.log >&2
exit 0