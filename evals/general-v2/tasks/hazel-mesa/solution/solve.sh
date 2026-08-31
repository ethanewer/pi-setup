#!/bin/bash
#
# hazel-mesa oracle. Does the real work: writes the compose-parsing +
# connection + CSV export program, then RUNS it on the visible stack to
# produce /app/telemetry.csv. Never reads /tests.
set -euo pipefail

SOLVER="/app/warehouse_dump.py"
OUT="/app/telemetry.csv"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Export the telemetry_readings table using credentials derived from a
compose-style stack description."""
import os
import re
import subprocess
import sys

SELECT_SQL = (
    "SELECT reading_id, sensor_id, reading, quality "
    "FROM telemetry_readings ORDER BY reading_id"
)


class BadStack(Exception):
    pass


def take_value(val):
    """Scalar value, honoring quoting and stripping unquoted trailing comments."""
    val = val.strip()
    if not val:
        return ""
    if val[0] in ('"', "'"):
        q = val[0]
        end = val.find(q, 1)
        if end == -1:
            raise BadStack("unterminated quote: %r" % val)
        return val[1:end]
    return re.split(r"\s+#", val, maxsplit=1)[0].strip()


def parse_compose(path):
    """Minimal parser for the documented compose-file subset."""
    with open(path, "r", encoding="utf-8") as fh:
        raw = fh.readlines()
    lines = []
    for ln in raw:
        if not ln.strip() or ln.lstrip().startswith("#"):
            continue
        lines.append((len(ln) - len(ln.lstrip(" ")), ln.strip()))

    pos = 0

    def parse_block(indent):
        nonlocal pos
        result = {}
        items = []
        while pos < len(lines):
            ind, content = lines[pos]
            if ind < indent:
                break
            if ind > indent:
                raise BadStack("unexpected indentation: %r" % content)
            if content.startswith("- ") or content == "-":
                item = take_value(content[2:]) if len(content) > 2 else ""
                pos += 1
                items.append(item)
                continue
            key, _, val = content.partition(":")
            key = take_value(key)
            val = val.strip()
            pos += 1
            if val == "":
                if pos < len(lines) and lines[pos][0] > indent:
                    result[key] = parse_block(lines[pos][0])
                else:
                    result[key] = {}
            elif val == "{}":
                result[key] = {}
            else:
                result[key] = take_value(val)
        if items and result:
            raise BadStack("mixed mapping/sequence block")
        if items:
            return items
        return result

    doc = parse_block(0)
    if not isinstance(doc, dict) or not isinstance(doc.get("services"), dict):
        raise BadStack("no services: mapping")
    return doc


def find_db_service(doc):
    for name, svc in doc["services"].items():
        if not isinstance(svc, dict):
            continue
        image = str(svc.get("image") or "")
        if image.startswith("postgres:"):
            return name, svc
    raise BadStack("no postgres service")


def host_port(svc):
    ports = svc.get("ports")
    if not isinstance(ports, list) or not ports:
        raise BadStack("postgres service has no ports mapping")
    entry = str(ports[0]).strip()
    parts = entry.split(":")
    if len(parts) < 2:
        raise BadStack("bad ports entry: %r" % entry)
    return int(parts[-2])


def db_creds(svc):
    env = svc.get("environment")
    if not isinstance(env, dict):
        raise BadStack("postgres service has no environment mapping")
    out = {}
    for key in ("POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD"):
        if key not in env:
            raise BadStack("missing %s" % key)
        out[key] = str(env[key])
    return out["POSTGRES_DB"], out["POSTGRES_USER"], out["POSTGRES_PASSWORD"]


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: warehouse_dump.py <compose_file> <output_csv>\n")
        return 2
    compose_path, out_path = argv[1], argv[2]
    try:
        doc = parse_compose(compose_path)
        name, svc = find_db_service(doc)
        port = host_port(svc)
        db, user, password = db_creds(svc)
    except (BadStack, OSError, ValueError) as exc:
        sys.stderr.write("warehouse_dump: %s\n" % exc)
        return 2

    env = dict(os.environ, PGPASSWORD=password)
    try:
        proc = subprocess.run(
            ["psql", "-X", "-w", "-h", "127.0.0.1", "-p", str(port),
             "-U", user, "-d", db, "-v", "ON_ERROR_STOP=1", "-q",
             "-c", "\\copy (%s) TO STDOUT WITH (FORMAT csv, HEADER true)" % SELECT_SQL],
            env=env, capture_output=True, text=True, timeout=60,
        )
    except subprocess.TimeoutExpired:
        sys.stderr.write("warehouse_dump: psql timed out\n")
        return 1
    if proc.returncode != 0:
        sys.stderr.write("warehouse_dump: connection/query failed: %s"
                         % proc.stderr.strip())
        return 1
    data = proc.stdout
    if not data.endswith("\n"):
        data += "\n"
    tmp = out_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(data)
    os.replace(tmp, out_path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY
chmod +x "$SOLVER"

# ---- 2. Run the produced program on the visible stack (live database).
python3 "$SOLVER" /app/warehouse/compose.yaml "$OUT"

# ---- 3. Sanity: the deliverable CSV has the header and rows.
grep -q '^reading_id,sensor_id,reading,quality$' "$OUT"
[ "$(wc -l < "$OUT")" -ge 2 ]

echo "hazel-mesa oracle complete -> $SOLVER and $OUT"
exit 0
