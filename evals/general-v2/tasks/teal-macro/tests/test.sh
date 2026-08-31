#!/bin/bash
# Verifier for teal-macro: sources /app/macros.vim in a clean headless Vim,
# verifies the buffer is untouched by sourcing, measures the total macro
# keystroke budget, then APPLIES register 'a' once per line to the visible
# source and to every hidden source file and compares byte-for-byte. Writes
# REWARD (0/1) to /logs/verifier/reward.txt. Never crashes on malformed output.
set -u
mkdir -p /logs/verifier

BUDGET=40
PRISTINE_SOURCE_SHA="9d9d57c2946f7c89b069dea497914022b896abe37ce0ec3e9cbb9fe5602f474f"

reward=0
fail_reason=""

if [ ! -f /app/macros.vim ] || [ ! -s /app/macros.vim ]; then
  fail_reason="missing or empty /app/macros.vim"
elif [ ! -f /app/source.txt ] || [ ! -f /app/wanted.txt ]; then
  fail_reason="visible fixtures missing"
else
  actual_sha="$(sha256sum /app/source.txt | awk '{print $1}')"
  if [ "$actual_sha" != "$PRISTINE_SOURCE_SHA" ]; then
    fail_reason="/app/source.txt was modified"
  fi
fi

run_vim_case () {
  # $1 source file, $2 output file, $3 flag file, $4 budget file
  TSRC="$1" TOUT="$2" TFLAG="$3" TBUD="$4" \
    timeout 60 vim -Nu NONE -n -i NONE --not-a-term -es -S /tests/driver.vim \
    >/dev/null 2>&1
  return $?
}

if [ -z "$fail_reason" ]; then
  # static checks: no functions/autocmds/mappings/commands/interpreter bridges
  if grep -qiE '\b(function|autocmd|command|com!|map|noremap|py3?|python|lua|ruby|perl)\b' /app/macros.vim; then
    fail_reason="macros.vim uses forbidden constructs (functions/autocmds/maps/interpreters)"
  fi
fi

if [ -z "$fail_reason" ]; then
  run_vim_case /app/source.txt /tmp/teal_out.txt /tmp/teal_flag.txt /tmp/teal_bud.txt
  python3 - "$BUDGET" <<'PY'
import sys
BUDGET = int(sys.argv[1])
fails = []
def read(p):
    try:
        return open(p).read()
    except Exception:
        return None
flag = read("/tmp/teal_flag.txt")
if flag is None:
    fails.append("sourcing produced no state (vim failed to run)")
elif "CLEAN" not in flag:
    fails.append("sourcing macros.vim modified the buffer")
bud = read("/tmp/teal_bud.txt")
if bud is None:
    fails.append("budget measurement missing")
else:
    lines = bud.strip().splitlines()
    try:
        total, len_a = int(lines[0].strip()), int(lines[1].strip())
    except Exception:
        fails.append("budget file malformed")
    else:
        if total > BUDGET:
            fails.append("macro budget %d exceeds %d" % (total, BUDGET))
        if len_a <= 0:
            fails.append("primary register 'a' is empty")
out = read("/tmp/teal_out.txt")
want = read("/app/wanted.txt")
if out is None or want is None:
    fails.append("transformed buffer or wanted fixture missing")
elif out.rstrip("\n") != want.rstrip("\n"):
    fails.append("macro application output mismatch on visible source")
# visible deliverable
tr = read("/app/transformed.txt")
if tr is None:
    fails.append("missing /app/transformed.txt")
elif tr.rstrip("\n") != want.rstrip("\n"):
    fails.append("/app/transformed.txt does not equal /app/wanted.txt")
print("verify failures:", fails)
sys.exit(1 if fails else 0)
PY
  if [ $? -eq 0 ]; then :; else fail_reason="visible case failed"; fi
fi

if [ -z "$fail_reason" ]; then
  # hidden sources: same macro, fresh files with different values/widths
  HID="/tests/hidden"
  if [ -d "$HID" ]; then
    for case in "$HID"/*/; do
      [ -f "$case/source.txt" ] || continue
      run_vim_case "$case/source.txt" /tmp/teal_out_h.txt /tmp/teal_flag_h.txt /tmp/teal_bud_h.txt
      python3 - "$case" "$BUDGET" <<'PY'
import os, sys
case, BUDGET = sys.argv[1], int(sys.argv[2])
fails = []
def read(p):
    try:
        return open(p).read()
    except Exception:
        return None
if "CLEAN" not in (read("/tmp/teal_flag_h.txt") or ""):
    fails.append("%s: sourcing modified buffer" % case)
bud = read("/tmp/teal_bud_h.txt")
try:
    if int(bud.strip().splitlines()[0]) > BUDGET:
        fails.append("%s: over budget" % case)
except Exception:
    fails.append("%s: budget unreadable" % case)
out = read("/tmp/teal_out_h.txt")
want = read(os.path.join(case, "wanted.txt"))
if out is None or want is None:
    fails.append("%s: output missing" % case)
elif out.rstrip("\n") != want.rstrip("\n"):
    fails.append("%s: transformed output mismatch" % case)
print("verify failures:", fails)
sys.exit(1 if fails else 0)
PY
      if [ $? -ne 0 ]; then fail_reason="hidden case $case failed"; break; fi
    done
  else
    fail_reason="no hidden cases directory"
  fi
fi

if [ -z "$fail_reason" ]; then
  reward=1
fi
echo "$reward" > /logs/verifier/reward.txt
if [ -n "$fail_reason" ]; then
  echo "verifier: $fail_reason" >&2
fi
exit 0
