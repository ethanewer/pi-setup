#!/usr/bin/env bash
# kedd semantic check suite. Green on the pristine tree: exercises workload
# parsing, the digest rule and the ordered journal writer. No opinion about
# the shutdown path.
set -euo pipefail
cd "$(dirname "$0")/.."

bash build.sh >/dev/null

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

java -cp build cairn.Check \
    workloads/sample/workload.txt "$WORK/check-journal.txt"

python3 - "$WORK/check-journal.txt" workloads/sample/workload.txt <<'PY'
import hashlib
import sys

journal_path, workload_path = sys.argv[1], sys.argv[2]
events = []
with open(workload_path, encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        ordinal, payload, width = line.split(",")
        events.append((int(ordinal), payload, int(width)))

with open(journal_path, encoding="utf-8") as fh:
    lines = [l.rstrip("\n") for l in fh if l.strip()]

want = {}
for k in range(min(60, len(events))):
    ordinal, payload, width = events[k]
    digest = hashlib.sha256(
        ("%d:%s:%d" % (ordinal, payload, width)).encode("utf-8")
    ).hexdigest()[:16]
    want[ordinal] = "%d|%s|%s" % (ordinal, payload, digest)

got = {}
for line in lines:
    ordinal, payload, digest = line.split("|")
    got[int(ordinal)] = line

if got != want:
    missing = sorted(set(want) - set(got))
    extra = sorted(set(got) - set(want))
    wrong = sorted(o for o in want if o in got and got[o] != want[o])
    raise SystemExit("check mismatch: missing=%s extra=%s wrong=%s"
                     % (missing[:5], extra[:5], wrong[:5]))

if len(lines) != len(want):
    raise SystemExit("check mismatch: %d journal lines, expected %d"
                     % (len(lines), len(want)))

print("kedd check: OK (%d entries, ordered, digests valid)" % len(want))
PY