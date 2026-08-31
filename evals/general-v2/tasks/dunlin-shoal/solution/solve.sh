#!/bin/bash
# Real oracle for dunlin-shoal: write the export.py program, then RUN it on
# the visible compose fixture to produce /app/snapshot.json. Never reads /tests.
set -eu

EXPORTER="/app/export.py"
OUT="/app/snapshot.json"

# Ensure the scenario instance is live (idempotent image infrastructure).
/opt/dunctl/dbctl.sh up

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$EXPORTER" <<'PY'
#!/usr/bin/env python3
"""Export the Larkspur telemetry archive described by a compose-style file.

Usage: python3 /app/export.py <compose_file> <output_json>
"""
import json
import os
import re
import subprocess
import sys
import tempfile


def parse_compose(path):
    """Minimal parser for the simple nested-mapping compose layout."""
    with open(path, "r", encoding="utf-8") as fh:
        lines = fh.readlines()

    def indent_of(line):
        return len(line) - len(line.lstrip(" "))

    # locate the service that declares POSTGRES_DB
    env = {}
    port = None
    in_services = False
    svc_indent = None
    in_env = False
    in_ports = False
    for raw in lines:
        line = raw.rstrip("\n")
        stripped = line.split("#", 1)[0].rstrip() if not line.lstrip().startswith("#") else ""
        if not stripped.strip():
            continue
        ind = indent_of(stripped)
        content = stripped.strip()
        if content == "services:":
            in_services = True
            continue
        if in_services and ind == 0:
            in_services = False
        if in_services and ind == 2 and content.endswith(":"):
            svc_indent = ind
            in_env = False
            in_ports = False
            continue
        if svc_indent is not None and ind > svc_indent:
            if content == "environment:":
                in_env, in_ports = True, False
                continue
            if content == "ports:":
                in_env, in_ports = False, True
                continue
            if in_env and ind >= 6 and ":" in content:
                k, _, v = content.partition(":")
                env[k.strip()] = v.strip().strip('"').strip("'")
            elif in_env and ind >= 6 and content.startswith("- "):
                pass
            if in_ports and content.startswith("- "):
                spec = content[2:].strip().strip('"').strip("'")
                left = spec.split(":")[0].strip()
                if left.isdigit():
                    port = int(left)
    return env, port


def main():
    if len(sys.argv) != 3:
        print("usage: export.py <compose_file> <output_json>", file=sys.stderr)
        return 2
    compose_path, out_path = sys.argv[1], sys.argv[2]
    env, port = parse_compose(compose_path)
    for key in ("POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD"):
        if key not in env or not env[key]:
            print("compose file missing %s" % key, file=sys.stderr)
            return 2
        if port is None:
            print("compose file missing published port", file=sys.stderr)
            return 2
    db, user, pw = env["POSTGRES_DB"], env["POSTGRES_USER"], env["POSTGRES_PASSWORD"]

    sql = ("SELECT station, metric, value FROM sensor_readings "
           "ORDER BY station ASC, metric ASC, value ASC, id ASC")
    tmp = tempfile.NamedTemporaryFile(mode="r", delete=False, suffix=".tsv")
    tmp.close()
    os.environ["PGPASSWORD"] = pw
    proc = subprocess.run(
        ["psql", "-h", "127.0.0.1", "-p", str(port), "-U", user, "-d", db,
         "-tA", "-F", "\t", "-v", "ON_ERROR_STOP=1", "-c", sql, "-o", tmp.name],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60,
    )
    if proc.returncode != 0:
        os.unlink(tmp.name)
        print("database query failed: %s" % proc.stderr.strip(), file=sys.stderr)
        return 1

    readings = []
    with open(tmp.name, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            station, metric, value = line.split("\t")
            readings.append([station, metric, int(value)])
    os.unlink(tmp.name)

    snapshot = {
        "database": db,
        "port": int(port),
        "row_count": len(readings),
        "readings": readings,
    }
    fd, staged = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(out_path)) or ".")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(snapshot, fh, indent=2)
        fh.write("\n")
    os.replace(staged, out_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$EXPORTER"

# 2. Run the produced program on the visible fixture to generate the output.
python3 "$EXPORTER" /app/deploy/compose.yaml "$OUT"

echo "solve.sh done -> $EXPORTER and $OUT"
ls -l "$EXPORTER" "$OUT"
