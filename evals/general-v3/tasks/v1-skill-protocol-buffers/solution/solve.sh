#!/bin/bash
set -euo pipefail

cat > /app/writer.py <<'PYEOF'
import sys
sys.path.insert(0, '/app')
import person_pb2

p = person_pb2.Person()
p.name = "Grace Hopper"
p.id = 7
p.email = "grace@example.org"

with open('/app/person.bin', 'wb') as f:
    f.write(p.SerializeToString())
PYEOF

python3 /app/writer.py
echo "wrote /app/person.bin"