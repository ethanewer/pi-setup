#!/bin/bash
# Real oracle for marlin-berth: write the setup.sh deliverable, then RUN it on
# the visible lists fixture to install the canonical mailing-list config and
# produce /app/list_report.json. Never reads /tests.
set -eu

SETUP="/app/setup.sh"
REPORT="/app/list_report.json"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SETUP" <<'SH'
#!/bin/bash
# Gullwing Press mailing-list installer (canonical postfix virtual map).
set -eu

LISTS="${1:-/app/fixtures/lists.tsv}"
MAP=/etc/postfix/virtual_lists
REPORT=/app/list_report.json

[ -f "$LISTS" ] || { echo "lists file not found: $LISTS" >&2; exit 1; }

python3 - "$LISTS" "$MAP" "$REPORT" <<'PY'
import json, os, subprocess, sys

lists_path, map_path, report_path = sys.argv[1], sys.argv[2], sys.argv[3]
BEGIN, END = "# BEGIN gullwing-lists", "# END gullwing-lists"

lists = []
with open(lists_path, encoding="utf-8") as fh:
    for raw in fh:
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            print("bad line (need address<TAB>target): %r" % line, file=sys.stderr)
            sys.exit(1)
        addr, target = parts[0].strip(), parts[1].strip()
        if "@" not in addr or not target:
            print("bad list entry: %r" % line, file=sys.stderr)
            sys.exit(1)
        lists.append((addr, target))
if not lists:
    print("no lists found in %s" % lists_path, file=sys.stderr)
    sys.exit(1)

# local accounts for local targets (idempotent)
for addr, target in lists:
    if "@" not in target:
        if subprocess.run(["getent", "passwd", target],
                          capture_output=True).returncode != 0:
            subprocess.run(["useradd", "-m", target], check=True)

# canonical virtual map + make postfix honor it
with open(map_path, "w", encoding="utf-8") as fh:
    for addr, target in sorted(lists):
        fh.write("%s\t%s\n" % (addr, target))
subprocess.run(["postconf", "-e", "virtual_alias_maps = hash:%s" % map_path],
               check=True)
subprocess.run(["postmap", map_path], check=True)

# aliases: rewrite the managed block only
aliases = "/etc/aliases"
existing = []
if os.path.exists(aliases):
    with open(aliases, encoding="utf-8") as fh:
        existing = fh.readlines()
out, in_block = [], False
for line in existing:
    if line.strip() == BEGIN:
        in_block = True
        continue
    if line.strip() == END:
        in_block = False
        continue
    if not in_block:
        out.append(line)
block = [BEGIN + "\n"]
for addr, target in sorted(lists):
    if "@" not in target:
        block.append("%s: %s\n" % (addr.split("@", 1)[0], target))
block.append(END + "\n")
with open(aliases, "w", encoding="utf-8") as fh:
    fh.writelines(out)
    fh.writelines(block)
subprocess.run(["postalias", aliases], check=True)

# report
def kind(t):
    return "external" if "@" in t else "local"

report = {
    "map_path": map_path,
    "lists": [{"address": a, "target": t, "kind": kind(t)} for a, t in sorted(lists)],
}
tmp = report_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=2)
    fh.write("\n")
os.replace(tmp, report_path)
PY

echo "setup: canonical map installed at $MAP; report at $REPORT"
SH
chmod +x "$SETUP"

# 2. Run the produced program on the visible fixture (installs config + report).
bash "$SETUP"

echo "solve.sh done -> $SETUP and $REPORT"
ls -l "$SETUP" "$REPORT" /etc/postfix/virtual_lists /etc/postfix/virtual_lists.db
