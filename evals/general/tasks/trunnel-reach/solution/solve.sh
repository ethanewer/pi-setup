#!/bin/bash
# Oracle for trunnel-reach: install the reference solver as the deliverable and
# prove it recovers an accepted input for the visible binary.
set -eu
cp /solution/solver.py /app/solve.py
python3 /app/solve.py /app/challenge/crackme > /tmp/recovered.bin
python3 - <<'PY'
import subprocess
data = open('/tmp/recovered.bin', 'rb').read().rstrip(b'\n')
assert len(data) == 16, len(data)
p = subprocess.run(['/app/challenge/crackme'], input=data, capture_output=True)
assert p.returncode == 0 and b'ACCESS GRANTED' in p.stdout, (p.returncode, p.stdout)
print('oracle: recovered %r accepted by the visible binary' % data)
PY