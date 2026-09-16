#!/bin/sh
set -eu

cp /solution/reproduce.py /app/reproduce.py
chmod +x /app/reproduce.py
test -d /app/freezegun_base
test -f /app/freezegun_base/freezegun/api.py

python3 - <<'PY'
from pathlib import Path

p = Path('/app/freezegun_base/freezegun/api.py')
s = p.read_text()
old = "        if self.as_kwarg:\n            kwargs[self.as_kwarg] = time_factory\n            result = func(*args, **kwargs)\n        else:\n            result = func(*args, **kwargs)\n"
new = "        elif self.as_kwarg:\n            kwargs[self.as_kwarg] = time_factory\n            result = func(*args, **kwargs)\n        else:\n            result = func(*args, **kwargs)\n"
if old not in s:
    raise SystemExit('expected pre-fix branch not found')
p.write_text(s.replace(old, new, 1))
PY

python3 /app/reproduce.py
