#!/bin/bash
# Oracle for anchor-quill: write the apply_lists program, then RUN it on the
# visible fixture so the canonical Postfix config is live.
set -eu

SOLVER="/app/apply_lists.py"
SPEC="/app/fixtures/lists.spec"

# ---- 1. Write the deliverable program (this IS the work, not a canned answer).
cat > "$SOLVER" <<'PY'
#!/usr/bin/env python3
"""Apply a Larkspur Labs mailing-list spec to the canonical Postfix map."""
import os
import subprocess
import sys

# postconf/postmap live in /usr/sbin, which may not be on PATH.
os.environ["PATH"] = "/usr/sbin:/usr/local/sbin:" + os.environ.get("PATH", "")

VIRTUAL = "/etc/postfix/virtual"
MAINCF = "/etc/postfix/main.cf"


def parse_spec(path):
    """Return {list_address: [destinations]} for all valid spec lines."""
    lists = {}
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            tokens = line.split()
            addr, dests = tokens[0], tokens[1:]
            if "@" not in addr or not dests:
                continue  # malformed line: skip, keep going
            lists[addr] = dests
    return lists


def main():
    if len(sys.argv) != 2:
        print("usage: apply_lists.py <spec_file>", file=sys.stderr)
        return 2
    lists = parse_spec(sys.argv[1])

    # The canonical map is REPLACED by the spec's contents (idempotent).
    with open(VIRTUAL, "w", encoding="utf-8") as fh:
        for addr in sorted(lists):
            fh.write("%s %s\n" % (addr, ",".join(lists[addr])))

    # Ensure main.cf declares the canonical map.
    if not os.path.exists(MAINCF):
        open(MAINCF, "a").close()
    subprocess.run(
        ["postconf", "-e", "virtual_alias_maps=hash:/etc/postfix/virtual"],
        check=True, capture_output=True,
    )
    # Rebuild the map database so Postfix honors it.
    subprocess.run(["postmap", VIRTUAL], check=True, capture_output=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
chmod +x "$SOLVER"

# ---- 2. Run the produced program on the visible fixture.
python3 "$SOLVER" "$SPEC"

echo "solve.sh done -> $SOLVER applied $SPEC to /etc/postfix/virtual"
ls -l "$SOLVER" /etc/postfix/virtual /etc/postfix/virtual.db
