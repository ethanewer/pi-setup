#!/bin/bash
set -u
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt

reward=0.0
clean=0
editsok=0

# --- narrow edit boundary check --------------------------------------
if [ -f /app/report.tex ] && [ -f /tests/original.tex ]; then
  tr -d '\r' < /app/report.tex > /tmp/_agent.tex 2>/dev/null
  tr -d '\r' < /tests/original.tex > /tmp/_orig.tex 2>/dev/null
  diff /tmp/_orig.tex /tmp/_agent.tex > /tmp/_diff.txt 2>/dev/null
  removed=$(grep -c '^<' /tmp/_diff.txt 2>/dev/null)
  added=$(grep -c '^>' /tmp/_diff.txt 2>/dev/null)
  if [ "$added" -le 2 ] && [ "$removed" -le 1 ]; then
    editsok=1
  fi
fi

# --- clean compile check ----------------------------------------------
rm -rf /tmp/ltx; mkdir -p /tmp/ltx
if [ -f /app/report.tex ]; then
  tr -d '\r' < /app/report.tex > /tmp/ltx/report.tex 2>/dev/null
  cd /tmp/ltx
  pdflatex -interaction=nonstopmode report.tex >/dev/null 2>&1
  pdflatex -interaction=nonstopmode report.tex >/dev/null 2>&1
  if [ -f report.pdf ] && [ "$(stat -c%s report.pdf 2>/dev/null || echo 0)" -gt 0 ]; then
    errs=$(grep -c '^!' report.log 2>/dev/null)
    emergency=0
    if grep -q "Emergency stop" report.log 2>/dev/null; then emergency=1; fi
    if [ "$errs" -eq 0 ] && [ "$emergency" -eq 0 ]; then
      clean=1
    fi
  fi
fi

# final deliverable /app/report.pdf should also exist
haspdf=0
if [ -f /app/report.pdf ] && [ "$(stat -c%s /app/report.pdf 2>/dev/null || echo 0)" -gt 0 ]; then
  haspdf=1
fi

if [ "$clean" -eq 1 ] && [ "$editsok" -eq 1 ] && [ "$haspdf" -eq 1 ]; then
  reward=1.0
elif [ "$clean" -eq 1 ]; then
  reward=0.5
fi
echo "$reward" > /logs/verifier/reward.txt