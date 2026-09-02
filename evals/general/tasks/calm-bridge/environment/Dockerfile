FROM bench-base:python-3.12

WORKDIR /app

# Scenario tooling: the generator (+ the fixture-format spec it encodes) that the
# agent may inspect and run to build local inputs while developing the
# deliverable. The task itself only needs the Python stdlib (sqlite3, os, json,
# csv, sys, time, tempfile).
COPY files/ /app/

# Declared dependency; numpy is optional for this task so never fail the build.
RUN timeout 120 python3 -m pip install --no-cache-dir numpy >/dev/null 2>&1 || true

# Confirm the generator imports and the visible fixture is intact.
RUN python3 -c "import sys; sys.path.insert(0,'/app/files'); import tool.gen; print('gen ok')"
RUN python3 - <<'PY'
import sqlite3, os
c = sqlite3.connect("/app/trade/ledger.db")
assert c.execute("select count(*) from contacts").fetchone()[0] > 0
assert os.path.exists("/app/trade/ledger.wal")
c.close()
print("visible fixture ok")
PY