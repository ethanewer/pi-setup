#!/bin/bash
# Real oracle for sedge-vault: write the export program, then RUN it on the
# visible stack fixture to produce /app/specimens.json. Never reads /tests.
set -eu

EXPORT="/app/export.py"
OUT="/app/specimens.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$EXPORT" <<'PY'
#!/usr/bin/env python3
"""Export the Sedgevault specimens table using credentials derived from a
compose-style stack file."""
import json
import re
import subprocess
import sys


def parse_stack(path):
    text = open(path, encoding="utf-8").read()

    def envval(key):
        m = re.search(r"^\s*%s\s*:\s*(.*)$" % key, text, re.M)
        if not m:
            raise ValueError("missing %s in stack file" % key)
        v = m.group(1).strip()
        if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
            v = v[1:-1]
        return v

    db = envval("POSTGRES_DB")
    user = envval("POSTGRES_USER")
    password = envval("POSTGRES_PASSWORD")

    m = re.search(r'^\s*-\s*"?(\d+)\s*:\s*5432"?\s*$', text, re.M)
    if not m:
        raise ValueError("missing published port mapping in stack file")
    port = m.group(1)
    return "127.0.0.1", port, user, password, db


def find_psql():
    import glob
    for pat in ("/usr/lib/postgresql/*/bin/psql",):
        hits = sorted(glob.glob(pat))
        if hits:
            return hits[-1]
    return "psql"


def main():
    stack_path, out_path = sys.argv[1], sys.argv[2]
    host, port, user, password, db = parse_stack(stack_path)
    psql = find_psql()
    sql = (
        "SELECT id, catalog_code, species, quadrant, "
        "collected_at::text, mass_g FROM public.specimens ORDER BY id"
    )
    proc = subprocess.run(
        [psql, "-h", host, "-p", port, "-U", user, "-d", db,
         "-tA", "-F", "\x1f", "-v", "ON_ERROR_STOP=1", "-c", sql],
        capture_output=True, text=True, timeout=90,
        env={"PATH": "/usr/bin:/bin:/usr/local/bin", "PGPASSWORD": password},
    )
    if proc.returncode != 0:
        sys.stderr.write("export: query failed: %s\n" % proc.stderr.strip())
        sys.exit(1)

    rows = []
    for line in proc.stdout.splitlines():
        line = line.rstrip("\n")
        if not line.strip():
            continue
        _id, code, species, quadrant, collected_at, mass_g = line.split("\x1f")
        rows.append({
            "catalog_code": code,
            "species": species,
            "quadrant": quadrant,
            "collected_at": collected_at,
            "mass_g": int(mass_g),
        })

    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(rows, fh, indent=2, ensure_ascii=False)


if __name__ == "__main__":
    main()
PY
chmod +x "$EXPORT"

# 2. Run the produced program on the visible stack fixture to generate the
#    second deliverable.
python3 "$EXPORT" /app/archive/stack.yaml "$OUT"

echo "solve.sh done -> $EXPORT and $OUT"
ls -l "$EXPORT" "$OUT"
