#!/bin/bash
#
# tl-briar-entity (tblite-skill family) oracle.
#
# 1. Installs /app/analyze_xxe.py (the analyzer deliverable).
# 2. Runs it against the pristine originals still sitting in /app/parsers
#    (a fresh container starts from the shipped image), producing
#    /app/xxe_audit.json: the true pre-patch verdicts.
# 3. Replaces every vulnerable parser in /app/parsers/ with its patched
#    (guarded) version; the already-safe parser is reinstalled unchanged.
# 4. Self-checks: the patched parsers must all come back "not vulnerable"
#    under the analyzer and must still parse every visible sample.
set -euo pipefail

cp /solution/analyze_xxe.py /app/analyze_xxe.py
chmod +x /app/analyze_xxe.py

# --- Audit the PRISTINE originals first (they are still the shipped ones).
python3 /app/analyze_xxe.py --parsers-dir /app/parsers --out /app/xxe_audit.json

# --- Install the patched parser deliverables.
cp /solution/patched/snippet_extract.py    /app/parsers/snippet_extract.py
cp /solution/patched/catalog_fetch.py      /app/parsers/catalog_fetch.py
cp /solution/patched/plain_text.py         /app/parsers/plain_text.py
cp /solution/patched/directive_loader.py   /app/parsers/directive_loader.py
cp /solution/patched/report_sieve.py       /app/parsers/report_sieve.py
chmod 0644 /app/parsers/*.py

# --- Self-check: patched state must be clean under the analyzer, and every
# parser must still extract the visible samples.
python3 - <<'PYEOF'
import glob
import json
import subprocess
import sys

PARSERS = ["snippet_extract.py", "catalog_fetch.py", "plain_text.py",
           "directive_loader.py", "report_sieve.py"]

r = subprocess.run(
    [sys.executable, "/app/analyze_xxe.py",
     "--parsers-dir", "/app/parsers",
     "--out", "/tmp/patched-audit.json", "--max-depth", "6"],
    capture_output=True, text=True, timeout=120)
if r.returncode != 0:
    print("oracle: analyzer run failed:\n%s" % r.stderr)
    sys.exit(1)

with open("/tmp/patched-audit.json", encoding="utf-8") as fh:
    patched = json.load(fh)
bad = [e["parser"] for e in patched["parsers"] if e["vulnerable"]]
if bad:
    print("oracle: patched parsers still flagged vulnerable: %s" % bad)
    sys.exit(1)

samples = sorted(glob.glob("/app/samples/*.xml"))
for name in PARSERS:
    for sample in samples:
        proc = subprocess.run(
            [sys.executable, "/app/parsers/" + name, sample],
            capture_output=True, text=True, timeout=60)
        if proc.returncode != 0 or not proc.stdout.startswith("OK "):
            print("oracle: %s failed on %s (rc=%s) out=%r"
                  % (name, sample, proc.returncode, proc.stdout[:80]))
            sys.exit(1)

with open("/app/xxe_audit.json", encoding="utf-8") as fh:
    audit = json.load(fh)
print("oracle: audit ->")
for entry in audit["parsers"]:
    print("  %-22s vulnerable=%-5s reasons=%s"
          % (entry["parser"], entry["vulnerable"], entry["reasons"]))
print("tl-briar-entity oracle complete")
PYEOF

echo "tl-briar-entity oracle complete"