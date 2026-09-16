#!/bin/sh
set -eu
mkdir -p /logs/verifier
reward=0
trap 'printf "%s\n" "$reward" > /logs/verifier/reward.txt' EXIT

test -x /app/repro_case.py
test "$(python /app/repro_case.py)" = REPRO_OK

python /app/triage.py --input /app/source/events.jsonl --output /tmp/rich-visible-report.txt
cat > /tmp/rich-visible-expected.txt <<'EOF'
Log triage report
Records: 4
Levels: CRITICAL=1, ERROR=1, WARNING=1, INFO=1, DEBUG=0
Components: worker=2, api=1, db=1
Events:
[2026-01-02T08:59:59Z] ERROR api: bad [request] "quoted"
[2026-01-02T09:00:01Z] CRITICAL db: connection failed
[2026-01-02T09:00:02Z] INFO worker: ready [literal]
[2026-01-02T09:00:02Z] WARNING worker: retry\path
EOF
cmp /tmp/rich-visible-report.txt /tmp/rich-visible-expected.txt
! grep -q '\033\|\033\[' /tmp/rich-visible-report.txt

for case in /tests/hidden/cases/*.jsonl; do
    name=$(basename "$case" .jsonl)
    python /app/triage.py --input "$case" --output "/tmp/$name.out"
    cmp "/tmp/$name.out" "/tests/hidden/expected/$name.txt"
done

for bad in /tests/hidden/invalid/*.jsonl; do
    if python /app/triage.py --input "$bad" --output /tmp/should-not-exist.txt >/tmp/invalid.stdout 2>/tmp/invalid.stderr; then
        exit 1
    fi
    test ! -s /tmp/should-not-exist.txt
    test -s /tmp/invalid.stderr
done

mkdir -p /tmp/rich-io-output
if python /app/triage.py --input /tests/hidden/cases/long-literal.jsonl --output /tmp/rich-io-output >/tmp/io.stdout 2>/tmp/io.stderr; then
    exit 1
fi
test -s /tmp/io.stderr
if python /app/triage.py --input /tests/hidden/does-not-exist.jsonl --output /tmp/io-report.txt >/tmp/io.stdout 2>/tmp/io.stderr; then
    exit 1
fi
test -s /tmp/io.stderr

reward=1
