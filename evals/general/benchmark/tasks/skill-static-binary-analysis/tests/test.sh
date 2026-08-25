#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/analysis.txt ]; then
  python3 - <<'PY' && reward=1
import subprocess, re

def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()

elf = sh("objdump -f /app/prog | sed -n 's/.*file format //p'")
entry_raw = sh("readelf -h /app/prog | sed -n 's/.*Entry point address:[[:space:]]*//p'")
entry = entry_raw.strip().lower()
secret_raw = sh("strings /app/prog | grep -o 'harbor-binary-secret-[0-9]*' | head -1")
secret = secret_raw.strip()

lines = [ln.strip() for ln in open('/app/analysis.txt') if ln.strip()]
assert len(lines) == 3, lines
got = {}
for ln in lines:
    k, _, v = ln.partition('=')
    got[k.strip()] = v.strip()

got_elf = got.get('elf')
# accept both the bare format value and the verbatim objdump phrasing
assert got_elf == elf or got_elf == f"file format {elf}", (got_elf, elf)
assert got.get('entry') == entry, (got.get('entry'), entry)
assert got.get('secret') == secret, (got.get('secret'), secret)
PY
fi
echo "$reward" > /logs/verifier/reward.txt