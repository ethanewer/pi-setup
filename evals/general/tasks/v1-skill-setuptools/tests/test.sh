#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0

if [ -f /app/output.txt ]; then
  ok=1
  # output.txt must be exactly 'hello harbor\n'
  line=$(cat /app/output.txt)
  if [ "$line" != "hello harbor" ]; then ok=0; fi

  # setup.py must import from setuptools, use setup(, name, version, packages
  if [ ! -f /app/setup.py ]; then ok=0; fi
  if [ -f /app/setup.py ]; then
    s=$(grep -c "setuptools" /app/setup.py) || 0
    d=$(grep -c "distutils" /app/setup.py) || 0
    n=$(grep -c "greetpkg" /app/setup.py) || 0
    v=$(grep -c "1.0.0" /app/setup.py) || 0
    if [ "$s" -lt 1 ] || [ "$d" -gt 0 ] || [ "$n" -lt 1 ] || [ "$v" -lt 1 ]; then ok=0; fi
  fi

  # package must be importable in this Python env
  if ! python3 -c "import greetpkg" 2>/dev/null; then ok=0; fi

  if [ "$ok" -eq 1 ]; then reward=1; fi
fi

echo "$reward" > /logs/verifier/reward.txt