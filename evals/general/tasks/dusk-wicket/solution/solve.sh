#!/bin/bash
#
# dusk-wicket oracle: install the complete linter deliverables from a
# pristine container.  It writes the extended CLI (region + next-statement
# suppression, incremental cache with --stats) and the three rule plugins,
# clears the cache so cache tests start from a known state, then runs a
# self-check over the shipped examples.  Never reads /tests.
set -euo pipefail

rm -rf /app/lintcache
mkdir -p /app/rules /app/lintcache

# 1. Extended CLI.
cp /solution/full_lint.py /app/lintkit/lint.py
chmod 0755 /app/lintkit/lint.py

# 2. Rule plugins.
cp /solution/rule_forbid_call.py /app/rules/forbid_call.py
cp /solution/rule_shadow_var.py /app/rules/shadow_var.py
cp /solution/rule_mut_default.py /app/rules/mut_default.py

# 3. Self-check: the engine must load all rules and produce deterministic
#    findings on the visible examples without crashing.
python3 /app/lintkit/lint.py --no-cache \
    /app/examples/sample1.mpy /app/examples/sample2.mpy \
    > /tmp/oracle_findings.json
python3 - <<'PY'
import json
data = json.load(open("/tmp/oracle_findings.json"))
ids = set()
for path, findings in data.items():
    ids.update(f["id"] for f in findings)
assert ids == {"forbid-call", "shadow-var", "mut-default"}, ids
assert data["/app/examples/sample2.mpy"], "expected findings in sample2"
print("dusk-wicket oracle self-check passed:", len(data), "files")
PY

echo "solve.sh done"
cat /tmp/oracle_findings.json