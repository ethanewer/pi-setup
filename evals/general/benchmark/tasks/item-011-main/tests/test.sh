#!/bin/bash
# Verifier for item-011-main: compare port.py output to GnuCOBOL reference on hidden input.
mkdir -p /logs/verifier
reward=0
WD=/tmp/verify011
rm -rf "$WD"; mkdir -p "$WD"

cp /tests/reference.cob "$WD/ref.cob"
if ! ( cd "$WD" && cobc -x -o ref ref.cob >/dev/null 2>&1 ); then
  echo "cobc compile failed" >> /logs/verifier/note.txt
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi
cp /tests/test_input.dat "$WD/data.dat"
( cd "$WD" && ./ref >/dev/null 2>&1 )
if [ ! -f "$WD/report.txt" ]; then
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi
if [ ! -f /app/port.py ]; then
  echo 0 > /logs/verifier/reward.txt
  exit 0
fi
cp /tests/test_input.dat /app/port_input.dat
python3 /app/port.py
if [ -f /app/port_output.txt ]; then
  python3 - <<'EOF'
import sys
exp = open("/tmp/verify011/report.txt","rb").read()
got = open("/app/port_output.txt","rb").read()
# tolerate CRLF/CR by normalizing newlines, but keep everything else byte-for-byte
norm = lambda b: b.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
reward = 1 if norm(exp) == norm(got) else 0
open("/logs/verifier/reward.txt","w").write(str(reward))
EOF
else
  echo 0 > /logs/verifier/reward.txt
fi